// main.swift
// Swift port of the Java WisconsinAnomalyDetection main class.
//
// Loads the University of Wisconsin Breast Cancer dataset,
// preprocesses it, runs anomaly detection training, and evaluates
// on a test set.

import Foundation

// MARK: - Configuration
let printHistograms = true
let numHistogramBins = 5

// MARK: - Load CSV Data

/// Locate the CSV file bundled with the executable.
func csvURL() -> URL {
    // When run via `swift run` the resource is copied beside binary.
    if let url = Bundle.module.url(
        forResource: "cleaned_wisconsin_cancer_data",
        withExtension: "csv") {
        return url
    }
    // Fallback: look in the working directory.
    return URL(fileURLWithPath:
        "Sources/AnomalyDetection/Resources/" +
        "cleaned_wisconsin_cancer_data.csv")
}

let csvContent: String
do {
    csvContent = try String(contentsOf: csvURL(), encoding: .utf8)
} catch {
    fputs("Error: could not read CSV file — \(error)\n", stderr)
    exit(1)
}

let rawLines = csvContent
    .components(separatedBy: .newlines)
    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    .filter { !$0.isEmpty }

var allExamples: [[Double]] = []

for line in rawLines {
    let parts = line.components(separatedBy: ",")
    guard parts.count >= 10 else { continue }

    var xs = parts.prefix(10).compactMap {
        Double($0.trimmingCharacters(in: .whitespaces))
    }
    guard xs.count == 10 else { continue }

    // Scale features 0–8 to [0, 1].
    for i in 0..<9 { xs[i] *= 0.1 }

    // Log-transform each feature toward a Gaussian distribution.
    var minVal =  Double.greatestFiniteMagnitude
    var maxVal = -Double.greatestFiniteMagnitude
    for i in 0..<9 {
        xs[i] = log(xs[i] + 1.2)
        if xs[i] < minVal { minVal = xs[i] }
        if xs[i] > maxVal { maxVal = xs[i] }
    }
    let range = maxVal - minVal
    if range > 0 {
        for i in 0..<9 { xs[i] = (xs[i] - minVal) / range }
    }

    // Map target label: 2 → 0.0 (benign), 4 → 1.0 (malignant).
    xs[9] = (xs[9] - 2.0) * 0.5

    allExamples.append(xs)
}

print("Loaded \(allExamples.count) examples from Wisconsin dataset.")

// MARK: - Print Histograms (optional)

let featureNames = [
    "Clump Thickness",
    "Uniformity of Cell Size",
    "Uniformity of Cell Shape",
    "Marginal Adhesion",
    "Single Epithelial Cell Size",
    "Bare Nuclei",
    "Bland Chromatin",
    "Normal Nucleoli",
    "Mitoses"
]

if printHistograms {
    for (idx, name) in featureNames.enumerated() {
        printHistogram(title: name,
                       data: allExamples,
                       colIndex: idx,
                       min: 0.0, max: 1.0,
                       numBins: numHistogramBins)
    }
}

// MARK: - Train Anomaly Detector

let detector = AnomalyDetection(
    numFeatures: 10, allExamples: allExamples)
detector.train()

// MARK: - Use the Trained Model for Inference

// Sample vectors (9 features, no label column).
let testMalignant: [Double] =
    [0.5, 1.0, 1.0, 0.8, 0.5, 0.5, 0.7, 1.0, 0.1]
let testBenign: [Double] =
    [0.5, 0.4, 0.5, 0.1, 0.8, 0.1, 0.3, 0.6, 0.1]

// Pad to 10 elements so probability() can use (numFeatures-1).
let malignantFull = testMalignant + [0.0]
let benignFull    = testBenign    + [0.0]

let malignantResult = detector.isAnomaly(malignantFull)
let benignResult    = detector.isAnomaly(benignFull)

print("\n\nUsing the trained model:")
print("malignant result = \(malignantResult), " +
      "benign result = \(benignResult)")
