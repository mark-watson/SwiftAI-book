// AnomalyDetection.swift
// Swift port of the Java AnomalyDetection class.
//
// Uses per-feature Gaussian distributions to model "normal" behaviour
// and identifies inputs whose probability falls below a learned epsilon
// threshold as anomalies.

import Foundation

// MARK: - AnomalyDetection

/// Gaussian-based anomaly-detection model.
///
/// Use this model when you have many "normal" (negative) training
/// examples and relatively few "anomaly" (positive) examples — an
/// unbalanced dataset.  The model fits a Gaussian distribution to
/// each feature using the training data, then finds an epsilon cutoff
/// that minimises errors on a held-out cross-validation set.
class AnomalyDetection {

    // MARK: Constants
    private static let sqrt2Pi: Double = 2.50662827463   // √(2π)

    // MARK: Hyperparameter
    /// Best epsilon found during cross-validation search.
    private(set) var bestEpsilon: Double = 0.02

    // MARK: Per-feature parameters (learned during init)
    private var mu: [Double]           // mean of each feature
    private var sigmaSquared: [Double] // variance of each feature
    private let numFeatures: Int

    // MARK: Split data sets
    private let trainingExamples: [[Double]]
    private let crossValidationExamples: [[Double]]
    private let testingExamples: [[Double]]

    // MARK: - Init

    /// Partition `allExamples` into training (≈60%),
    /// cross-validation (≈28%), and test (≈12%) sets,
    /// then compute the per-feature mean.
    ///
    /// - Parameters:
    ///   - numFeatures: Total columns including the target label.
    ///   - allExamples: 2-D array `[N][numFeatures]`. The *last*
    ///     column is the binary target: 0 = normal, 1 = anomaly.
    init(numFeatures: Int, allExamples: [[Double]]) {
        self.numFeatures = numFeatures

        var training: [[Double]] = []
        var crossValidation: [[Double]] = []
        var testing: [[Double]] = []

        let outcomeIndex = numFeatures - 1

        for example in allExamples {
            let r = Double.random(in: 0..<1)
            if r < 0.6 {
                // ~60% → training. Allow only normal examples
                // (label < 0.5), but let ~10% of anomalous examples
                // slip through — mirroring the real-world condition
                // where a few positives contaminate the training set.
                let isNormal = example[outcomeIndex] < 0.5
                let slipThrough = Double.random(in: 0..<1) < 0.1
                if isNormal || slipThrough {
                    training.append(example)
                }
            } else if Double.random(in: 0..<1) < 0.7 {
                crossValidation.append(example)
            } else {
                testing.append(example)
            }
        }

        self.trainingExamples = training
        self.crossValidationExamples = crossValidation
        self.testingExamples = testing

        // Initialise parameter arrays.
        var muArr = [Double](repeating: 0.0, count: numFeatures)
        self.sigmaSquared = [Double](
            repeating: 0.0, count: numFeatures)

        // Compute per-feature mean from training data.
        let n = Double(training.count)
        guard n > 0 else {
            self.mu = muArr
            return
        }
        for featureIdx in 0..<numFeatures {
            let sum = training.reduce(0.0) { $0 + $1[featureIdx] }
            muArr[featureIdx] = sum / n
        }
        self.mu = muArr
    }

    // MARK: - Public accessors
    func muValues()           -> [Double] { mu }
    func sigmaSquaredValues() -> [Double] { sigmaSquared }

    // MARK: - Training

    /// Search over 40 candidate epsilon values, pick the one with
    /// the lowest cross-validation error count, then retrain and
    /// evaluate on the test set.
    func train() {
        var bestErrorCount = Double.greatestFiniteMagnitude

        for loop in 0..<40 {
            let epsilon = 0.05 + 0.01 * Double(loop)
            let errorCount = trainHelper(epsilon: epsilon)
            if errorCount < bestErrorCount {
                bestErrorCount = errorCount
                bestEpsilon = epsilon
            }
        }
        print("\n**** Best epsilon value = \(bestEpsilon)")

        // Retrain with best epsilon to lock in sigma-squared values.
        _ = trainHelper(epsilon: bestEpsilon)

        // Evaluate on held-out test set.
        test(epsilon: bestEpsilon)
    }

    // MARK: - Inference

    /// Returns `true` when `x` is classified as an anomaly.
    ///
    /// - Parameter x: Feature vector (9 values; no label column).
    func isAnomaly(_ x: [Double]) -> Bool {
        return probability(x) < bestEpsilon
    }

    // MARK: - Private helpers

    /// Gaussian probability density averaged across features
    /// (skipping the label column).
    private func probability(_ x: [Double]) -> Double {
        var sum = 0.0
        for f in 0..<(numFeatures - 1) {
            let denom = AnomalyDetection.sqrt2Pi * sigmaSquared[f]
            guard denom > 0 else { continue }
            let exponent = -(x[f] - mu[f]) * (x[f] - mu[f])
            sum += (1.0 / denom) * exp(exponent)
        }
        return sum / Double(numFeatures)
    }

    /// Update sigma-squared for `epsilon`, count CV errors.
    @discardableResult
    private func trainHelper(epsilon: Double) -> Double {
        // Update variance estimates from training examples.
        for f in 0..<(numFeatures - 1) {
            let sumSq = trainingExamples.reduce(0.0) {
                let diff = $1[f] - mu[f]
                return $0 + diff * diff
            }
            sigmaSquared[f] =
                (1.0 / Double(numFeatures)) * sumSq
        }

        // Count errors on cross-validation set.
        var errorCount = 0.0
        let labelIdx = 9   // target label column index
        for x in crossValidationExamples {
            let pValue = probability(x)
            if x[labelIdx] > 0.5 {
                // Ground truth: ANOMALY — error if model says normal
                if pValue > epsilon { errorCount += 1 }
            } else {
                // Ground truth: NORMAL — error if model says anomaly
                if pValue < epsilon { errorCount += 1 }
            }
        }
        print("   cross_validation_error_count = " +
              "\(errorCount) for epsilon = \(epsilon)")
        return errorCount
    }

    /// Compute precision, recall, and F1 on the test set.
    private func test(epsilon: Double) {
        var falsePosCount = 0.0
        var falseNegCount = 0.0
        var truePosCount  = 0.0
        var trueNegCount  = 0.0

        let labelIdx = 9
        for x in testingExamples {
            let pValue = probability(x)
            if x[labelIdx] > 0.5 {
                // Ground truth: ANOMALY
                if pValue > epsilon {
                    falseNegCount += 1
                } else {
                    truePosCount += 1
                }
            } else {
                // Ground truth: NORMAL
                if pValue < epsilon {
                    falsePosCount += 1
                } else {
                    trueNegCount += 1
                }
            }
        }

        let precision = truePosCount == 0 ? 0.0
            : truePosCount / (truePosCount + falsePosCount)
        let recall = truePosCount == 0 ? 0.0
            : truePosCount / (truePosCount + falseNegCount)
        let f1 = (precision + recall) == 0 ? 0.0
            : 2 * precision * recall / (precision + recall)

        print("\n\n -- best epsilon       = \(bestEpsilon)")
        print(" -- test examples      = \(testingExamples.count)")
        print(" -- false positives    = \(falsePosCount)")
        print(" -- true  positives    = \(truePosCount)")
        print(" -- false negatives    = \(falseNegCount)")
        print(" -- true  negatives    = \(trueNegCount)")
        print(" -- precision          = \(precision)")
        print(" -- recall             = \(recall)")
        print(" -- F1                 = \(f1)")
    }
}
