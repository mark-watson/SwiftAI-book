// TensorBasics: MLTensor, compute policies, and async predictions.
//
//   swift run -c release TensorBasics

import CoreML
import Foundation
import MLSupport

func elapsed(_ start: ContinuousClock.Instant) -> String {
    let d = ContinuousClock.now - start
    return String(format: "%.1f ms", Double(d.components.attoseconds) / 1e15
                                      + Double(d.components.seconds) * 1000)
}

// MARK: 1. Building and transforming tensors

print("=== 1. MLTensor basics ===")
let a = MLTensor(shape: [2, 3], scalars: [1, 2, 3, 4, 5, 6], scalarType: Float.self)
let b = MLTensor(shape: [3, 2], scalars: [1, 0, 0, 1, 1, 1], scalarType: Float.self)
let bias = MLTensor([0, 1] as [Float])

// Core ML dispatches tensor operations asynchronously. `await shapedArray(of:)`
// waits for the result and copies it into a Swift value.
let product = a.matmul(b) + bias          // [2, 2], bias broadcasts over rows
let probabilities = product.softmax(alongAxis: -1)

print("a.shape = \(a.shape), b.shape = \(b.shape), product.shape = \(product.shape)")
print("a @ b + bias =", await product.shapedArray(of: Float.self).scalars)
print("row softmax  =", await probabilities.shapedArray(of: Float.self).scalars
        .map { String(format: "%.3f", $0) })
print("column means =", await a.mean(alongAxes: 0).shapedArray(of: Float.self).scalars)
print("a[..., 1...] =", await a[..., 1...].shapedArray(of: Float.self).scalars)

// MARK: 2. Semantic search with tensor algebra

print("\n=== 2. Cosine similarity search with MLTensor ===")
let embedder = try await Embedder()
let sentences = [
    "The referee stopped the match after a foul.",
    "Inflation rose as the central bank kept rates low.",
    "Sodium chloride dissolves easily in water.",
    "Regular exercise lowers the risk of heart disease.",
    "The striker scored twice in the final.",
]
let matrix = try await embedder.embed(batch: sentences)    // [5, 384]
let query = try await embedder.embed("Who won the football game?")

// Rows are unit length, so a matrix product gives cosine similarities.
let scores = matrix.matmul(query.transposed()).squeezingShape()   // [5]
let (topValues, topIndices) = scores.topK(3)
let values = await topValues.shapedArray(of: Float.self).scalars
let indices = await topIndices.shapedArray(of: Int32.self).scalars
for (score, index) in zip(values, indices) {
    print(String(format: "  %.3f  %@", score, sentences[Int(index)]))
}

// MARK: 3. Choosing hardware for tensor math

print("\n=== 3. withMLTensorComputePolicy ===")
let big = MLTensor(repeating: 0.5, shape: [1024, 1024])
for (name, policy) in [("cpuOnly", MLComputePolicy.cpuOnly),
                       ("cpuAndGPU", MLComputePolicy.cpuAndGPU)] {
    // Warm up once so the timing excludes one time setup.
    _ = await withMLTensorComputePolicy(policy) {
        await big.matmul(big).sum().shapedArray(of: Float.self)
    }
    let start = ContinuousClock.now
    let total = await withMLTensorComputePolicy(policy) {
        var t = big
        for _ in 0..<10 { t = t.matmul(big) / 512 }
        return await t.sum().shapedArray(of: Float.self).scalars[0]
    }
    print("  \(name.padding(toLength: 10, withPad: " ", startingAt: 0)) 10 chained 1024x1024 matmuls: \(elapsed(start))  (sum \(total))")
}

// MARK: 4. Async predictions: sequential versus concurrent

print("\n=== 4. Async prediction throughput ===")
let passages = try Documents.passages().map(\.text)
let corpus = Array(repeating: passages, count: 8).flatMap { $0 }
var start = ContinuousClock.now
for text in corpus { _ = try await embedder.embed(text) }
print("  sequential awaits:  \(corpus.count) embeddings in \(elapsed(start))")

start = ContinuousClock.now
_ = try await embedder.embed(batch: corpus)
print("  task group:         \(corpus.count) embeddings in \(elapsed(start))")
