// TrainModels: reproducible, code-first training with Create ML.
//
//   swift run TrainModels
//
// Part 1 uses the task level CreateML framework to train a text classifier
// (the topic router used by the LocalRAG capstone).
// Part 2 uses the composable CreateMLComponents framework to train and
// compare two tabular classifiers, then exports one as a Core ML model.

import CoreML
import CreateML
import CreateMLComponents
import Foundation
import MLSupport
import TabularData

// MARK: - Part 1: text classifier with CreateML

func trainTopicRouter() throws {
    print("=== Part 1: topic router (CreateML MLTextClassifier) ===")

    var queries = try DataFrame(contentsOfCSVFile: Paths.training.appending(path: "router_queries.csv"))

    // Augment the hand written queries with sentences from the documents
    // the RAG system will search, so the router learns their vocabulary.
    for topic in Documents.topics {
        for sentence in try Documents.sentences(for: topic) {
            queries.append(row: sentence, topic)
        }
    }
    print("examples: \(queries.rows.count)")

    let (trainSlice, testSlice) = queries.randomSplit(by: 0.8, seed: 7)
    let train = DataFrame(trainSlice)
    let test = DataFrame(testSlice)

    let candidates: [(String, MLTextClassifier.ModelAlgorithmType)] = [
        ("maxEnt", .maxEnt(revision: 1)),
        ("BERT transfer", .transferLearning(.bertEmbedding, revision: 1)),
    ]

    var best: (name: String, model: MLTextClassifier, accuracy: Double)?
    for (name, algorithm) in candidates {
        let start = Date()
        let params = MLTextClassifier.ModelParameters(
            validation: .split(strategy: .automatic), algorithm: algorithm, language: .english)
        let classifier = try MLTextClassifier(trainingData: train, textColumn: "text",
                                              labelColumn: "label", parameters: params)
        let metrics = classifier.evaluation(on: test, textColumn: "text", labelColumn: "label")
        let accuracy = 1.0 - metrics.classificationError
        print(String(format: "%-14@ test accuracy %.3f  (%.1f s)",
                     name, accuracy, Date().timeIntervalSince(start)))
        if best == nil || accuracy > best!.accuracy {
            best = (name, classifier, accuracy)
        }
    }

    guard let best else { return }
    let metadata = MLModelMetadata(
        author: "Mark Watson",
        shortDescription: "Routes a question to chemistry, economics, health, sports, or off_topic",
        version: "1.0")
    let output = Paths.model("TopicRouter.mlmodel")
    try best.model.write(to: output, metadata: metadata)
    print("saved \(best.name) router to \(output.lastPathComponent)")

    for question in ["Why does salt dissolve in water?", "Who invented basketball?",
                     "Write a haiku about cats"] {
        let scores = try best.model.predictionWithConfidence(from: question)
        let top = scores.max { $0.value < $1.value }!
        print(String(format: "  %-36@ -> %@ (%.2f)", question, top.key, top.value))
    }
}

// MARK: - Part 2: tabular classifiers with CreateMLComponents

typealias Example = AnnotatedFeature<MLShapedArray<Float>, String>

func loadCancerExamples() throws -> [Example] {
    let text = try String(contentsOf: Paths.training.appending(path: "wisconsin_cancer.csv"),
                          encoding: .utf8)
    return text.split(whereSeparator: \.isNewline).compactMap { line in
        let values = line.split(separator: ",").compactMap {
            Float($0.trimmingCharacters(in: .whitespaces))
        }
        guard values.count == 10 else { return nil }
        // Column 10 is the class: 2 = benign, 4 = malignant.
        let label = values[9] == 4 ? "malignant" : "benign"
        return Example(feature: MLShapedArray(scalars: Array(values[0..<9]), shape: [9]),
                       annotation: label)
    }
}

func report(_ name: String, on test: [Example],
            classify: (MLShapedArray<Float>) async throws -> ClassificationDistribution<String>)
async throws {
    var pairs: [(predicted: String, label: String)] = []
    for example in test {
        let distribution = try await classify(example.feature)
        pairs.append((distribution.mostLikelyLabel!, example.annotation))
    }
    let metrics = ClassificationMetrics(pairs)
    print(String(format: "%-22@ accuracy %.3f  malignant precision %.3f recall %.3f",
                 name, metrics.accuracy,
                 metrics.precisionScore(label: "malignant"),
                 metrics.recallScore(label: "malignant")))
}

func trainCancerClassifiers() async throws {
    print("\n=== Part 2: Wisconsin cancer data (CreateMLComponents) ===")
    var generator = SeededGenerator(seed: 42)
    let examples = try loadCancerExamples().shuffled(using: &generator)
    let split = Int(Double(examples.count) * 0.8)
    let train = Array(examples[..<split])
    let test = Array(examples[split...])
    print("train \(train.count), test \(test.count)")

    var lrConfig = LogisticRegressionClassifier<Float, String>.Configuration()
    lrConfig.maximumIterations = 50
    let logistic = LogisticRegressionClassifier<Float, String>(
        labels: ["benign", "malignant"], configuration: lrConfig)
    let logisticModel = try await logistic.fitted(to: train)
    try await report("logistic regression", on: test) {
        try await logisticModel.applied(to: $0)
    }

    var mlpConfig = FullyConnectedNetworkConfiguration()
    mlpConfig.hiddenUnitCounts = [16, 8]
    mlpConfig.maximumIterations = 200
    mlpConfig.randomSeed = 42
    let mlp = FullyConnectedNetworkClassifier<Float, String>(
        labels: ["benign", "malignant"], configuration: mlpConfig)
    let mlpModel = try await mlp.fitted(to: train)
    try await report("fully connected net", on: test) {
        try await mlpModel.applied(to: $0)
    }

    // Any CreateMLComponents transformer can be exported as a Core ML model.
    let output = Paths.model("CancerClassifier.mlpackage")
    try? FileManager.default.removeItem(at: output)
    try mlpModel.export(to: output)
    print("exported \(output.lastPathComponent)")

    // Round trip: load the exported file with plain Core ML.
    let coreML = try await ModelStore.load("CancerClassifier.mlpackage")
    let description = coreML.modelDescription
    print("Core ML inputs:  \(description.inputDescriptionsByName.keys.sorted())")
    print("Core ML outputs: \(description.outputDescriptionsByName.keys.sorted())")
}

// MARK: - main

try FileManager.default.createDirectory(at: Paths.models, withIntermediateDirectories: true)
try trainTopicRouter()
try await trainCancerClassifiers()
