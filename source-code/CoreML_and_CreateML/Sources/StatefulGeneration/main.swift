// StatefulGeneration: a multifunction Core ML model with a KV-cache.
//
//   swift run -c release StatefulGeneration "Sport is"
//
// CharLM.mlpackage holds two functions that share one copy of the weights:
//
//   generate  input_ids [1,1], position [1]  -> logits [1,V]
//             keyCache and valueCache live in an MLState between calls
//   score     input_ids [1,128]              -> log_probs [1,128,V]
//             stateless; recomputes attention over the whole window
//
// We select a function with MLModelConfiguration.functionName.

import CoreML
import Foundation
import MLSupport

let context = 128

func milliseconds(since start: ContinuousClock.Instant) -> String {
    let d = ContinuousClock.now - start
    return String(format: "%.1f ms", Double(d.components.seconds) * 1000
                                     + Double(d.components.attoseconds) / 1e15)
}

struct CharVocab {
    let chars: [Character]
    let index: [Character: Int32]

    init() throws {
        let data = try Data(contentsOf: Paths.model("charlm_vocab.json"))
        chars = try JSONDecoder().decode([String].self, from: data).map { Character($0) }
        index = Dictionary(uniqueKeysWithValues: chars.enumerated().map { ($1, Int32($0)) })
    }

    func encode(_ text: String) -> [Int32] { text.compactMap { index[$0] } }
}

/// Temperature sampling from a logits or log-probability row.
func sample(_ row: MLTensor, temperature: Float, using rng: inout SeededGenerator) async -> Int32 {
    let probs = await (row / temperature).softmax().shapedArray(of: Float.self).scalars
    var r = Float.random(in: 0..<1, using: &rng)
    for (i, p) in probs.enumerated() {
        r -= p
        if r <= 0 { return Int32(i) }
    }
    return Int32(probs.count - 1)
}

func tensor(_ values: [Int32], shape: [Int]) -> MLTensor {
    MLTensor(shape: shape, scalars: values, scalarType: Int32.self)
}

// MARK: - KV-cache generation with MLState

func generateWithState(_ model: MLModel, prompt: [Int32], count: Int,
                       vocab: CharVocab) async throws -> String {
    guard !prompt.isEmpty else { return "" }
    let prompt = Array(prompt.suffix(context - 1))
    let state = model.makeState()
    var rng = SeededGenerator(seed: 1)
    var logits: MLTensor?

    // Prefill: feed the prompt one character at a time to fill the cache.
    for (position, id) in prompt.enumerated() {
        let out = try await model.prediction(
            from: ["input_ids": tensor([id], shape: [1, 1]),
                   "position": tensor([Int32(position)], shape: [1])],
            using: state)
        logits = out["logits"]
    }

    var output = ""
    var position = prompt.count
    while output.count < count && position < context {
        let next = await sample(logits!.squeezingShape(), temperature: 0.8, using: &rng)
        output.append(vocab.chars[Int(next)])
        let out = try await model.prediction(
            from: ["input_ids": tensor([next], shape: [1, 1]),
                   "position": tensor([Int32(position)], shape: [1])],
            using: state)
        logits = out["logits"]
        position += 1
    }
    return output
}

// MARK: - Generation without a cache, using the "score" function

/// Left pads with spaces so the newest character is always in the last slot.
func window(_ ids: [Int32], pad: Int32) -> [Int32] {
    let tail = Array(ids.suffix(context))
    return Array(repeating: pad, count: context - tail.count) + tail
}

func generateByRecomputing(_ model: MLModel, prompt: [Int32], count: Int,
                           vocab: CharVocab) async throws -> String {
    var rng = SeededGenerator(seed: 1)
    var ids = prompt
    let pad = vocab.index[" "]!
    var output = ""
    while output.count < count {
        let out = try await model.prediction(
            from: ["input_ids": tensor(window(ids, pad: pad), shape: [1, context])])
        let lastRow = out["log_probs"]![0, context - 1]       // [V]
        let next = await sample(lastRow, temperature: 0.8, using: &rng)
        output.append(vocab.chars[Int(next)])
        ids.append(next)
    }
    return output
}

/// Average log-probability per character: higher means "looks like the
/// training text". A cheap in-distribution signal for a guardrail.
func meanLogProb(_ model: MLModel, text: String, vocab: CharVocab) async throws -> Float {
    let rawIds = vocab.encode(text)
    guard rawIds.count >= 2 else { return 0 }
    let ids = Array(rawIds.suffix(context))
    let padded = window(ids, pad: vocab.index[" "]!)
    let out = try await model.prediction(from: ["input_ids": tensor(padded, shape: [1, context])])
    let logProbs = await out["log_probs"]!.shapedArray(of: Float.self)
    let first = context - ids.count
    var total: Float = 0
    for t in first..<(context - 1) {
        total += logProbs[0, t, Int(padded[t + 1])].scalar!
    }
    return total / Float(ids.count - 1)
}

// MARK: - main

let vocab = try CharVocab()
let promptText = CommandLine.arguments.dropFirst().first ?? "Sport is"
let prompt = vocab.encode(promptText)
let newChars = 80

let scoreModel = try await ModelStore.load("CharLM.mlpackage", functionName: "score")
print("score function inputs: \(scoreModel.modelDescription.inputDescriptionsByName.keys.sorted())")

do {
    let generateModel = try await ModelStore.load("CharLM.mlpackage", functionName: "generate")
    print("generate function states: \(generateModel.modelDescription.stateDescriptionsByName.keys.sorted())")
    let start = ContinuousClock.now
    let text = try await generateWithState(generateModel, prompt: prompt, count: newChars, vocab: vocab)
    print("\n[KV-cache, \(milliseconds(since: start))]\n\(promptText)\(text)")
} catch {
    print("\nThe stateful \"generate\" function did not load on this system:")
    print("  \(error.localizedDescription)")
    print("Falling back to the stateless \"score\" function.")
}

let start = ContinuousClock.now
let text = try await generateByRecomputing(scoreModel, prompt: prompt, count: newChars, vocab: vocab)
print("\n[recompute full window, \(milliseconds(since: start))]\n\(promptText)\(text)")

print("\nMean log-probability per character (score function):")
for sample in ["Sports are usually governed by rules to ensure fair competition.",
               "Economics analyses the production of goods and services.",
               "zqx vvk jjjq plmw kkkkk qqq"] {
    let value = try await meanLogProb(scoreModel, text: sample, vocab: vocab)
    print(String(format: "  %7.3f  %@", value, sample))
}
