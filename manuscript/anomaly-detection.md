# Anomaly Detection

Anomaly detection models shine in one very specific class of problem: when you have many "normal" (negative) examples but relatively few "anomaly" (positive) examples — an *unbalanced* training set. The strategy is to ignore positive examples during training, build a statistical model of what "normal" looks like, and then flag any input that looks too different from that model.

If your training data is roughly balanced between negative and positive classes, you should use a supervised classification model instead. Reserve anomaly detection for situations where normal examples vastly outnumber anomalies.

## Motivation

The University of Wisconsin Breast Cancer dataset appears several times in this book. Other chapters use it with supervised learning, where both benign and malignant examples are available in roughly equal numbers. This chapter deliberately discards most of the malignant examples from training to simulate the real-world case where anomalies are rare.

The data preparation strategy is:

- Split all examples randomly into training (~60%), cross-validation (~28%), and test (~12%) sets.
- From the training partition, keep only benign ("normal") examples — but let about 10% of malignant examples slip through, mirroring the reality that some anomalies will always contaminate a real-world training set.
- Use the cross-validation set to search for a good value of the hyperparameter epsilon.
- Use the test set to compute precision, recall, and F1.

## The Gaussian Model

The algorithm models each feature independently with a Gaussian (bell-curve) distribution. For feature *j*, we learn the mean μ_j and the variance σ²_j from the training data. Given a new input vector **x**, the probability assigned by the model is the average of the Gaussian densities across all features:

```
p(x) = (1/n) Σ [ 1/(√(2π) · σ²_j) · exp(-(x_j - μ_j)²) ]
```

If `p(x)` falls *below* epsilon, the input is flagged as an anomaly.

The mean is easy to compute from training data. Variance is:

```
σ² = (1/m) Σ (x_i - μ)²
```

Epsilon is a *hyperparameter* that we tune against the cross-validation set rather than learning it from training data directly.

## Swift Implementation Overview

The Swift port is structured identically to the original Java version but uses idiomatic Swift: value-type arrays (`[[Double]]`), `guard` for safety, `Bundle.module` for bundled resources, and `Double.random(in:)` instead of `Math.random()`.

Three source files make up the package:

| File | Role |
|---|---|
| `AnomalyDetection.swift` | Core model class |
| `PrintHistogram.swift` | ASCII histogram utility |
| `main.swift` | Data loading, preprocessing, training, inference |

## `AnomalyDetection` Class

The class is initialised with the full example array. The initialiser partitions data into training, cross-validation, and test sets, then computes per-feature means.

{lang="swift",linenos=on}
~~~~~~~~
class AnomalyDetection {

    private static let sqrt2Pi: Double = 2.50662827463

    private(set) var bestEpsilon: Double = 0.02
    private var mu: [Double]
    private var sigmaSquared: [Double]
    private let numFeatures: Int

    private let trainingExamples: [[Double]]
    private let crossValidationExamples: [[Double]]
    private let testingExamples: [[Double]]

    init(numFeatures: Int, allExamples: [[Double]]) {
        self.numFeatures = numFeatures
        var training: [[Double]] = []
        var crossValidation: [[Double]] = []
        var testing: [[Double]] = []
        let outcomeIndex = numFeatures - 1

        for example in allExamples {
            let r = Double.random(in: 0..<1)
            if r < 0.6 {
                if example[outcomeIndex] < 0.5 || Double.random(in: 0..<1) < 0.1 {
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

        var muArr = [Double](repeating: 0.0, count: numFeatures)
        self.sigmaSquared = [Double](repeating: 0.0, count: numFeatures)
        let n = Double(training.count)
        for featureIdx in 0..<numFeatures {
            let sum = training.reduce(0.0) { $0 + $1[featureIdx] }
            muArr[featureIdx] = sum / n
        }
        self.mu = muArr
    }
}
~~~~~~~~

### Training: Searching for the Best Epsilon

The `train()` method loops over 40 candidate epsilon values from 0.05 to 0.44, calling `trainHelper(epsilon:)` for each. The candidate that produces the fewest cross-validation errors is retained.

{lang="swift",linenos=on}
~~~~~~~~
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
    _ = trainHelper(epsilon: bestEpsilon)
    test(epsilon: bestEpsilon)
}
~~~~~~~~

### The Gaussian Probability Function

The private method `probability(_:)` computes the model score for a single input vector. Note that the last element of the vector is the label column and is skipped.

{lang="swift",linenos=on}
~~~~~~~~
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
~~~~~~~~

### Public Inference

After training, you can classify any new input vector with `isAnomaly(_:)`:

{lang="swift",linenos=on}
~~~~~~~~
func isAnomaly(_ x: [Double]) -> Bool {
    return probability(x) < bestEpsilon
}
~~~~~~~~

## Preprocessing the Wisconsin Data

Raw feature values range from 1 to 10. The `main.swift` file applies two preprocessing steps:

1. **Scale** each of the 9 features by 0.1 to put them in the range [0, 1].
2. **Log-transform** each feature with `log(x + 1.2)` and then min-max normalise back to [0, 1]. This pushes the heavy-tailed distributions closer to a Gaussian shape, which the model assumes.

The label column (originally 2 for benign, 4 for malignant) is mapped to 0.0 and 1.0 respectively.

{lang="swift",linenos=on}
~~~~~~~~
for i in 0..<9 { xs[i] *= 0.1 }

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

xs[9] = (xs[9] - 2.0) * 0.5
~~~~~~~~

## Feature Histograms

Before training it is worth checking that the data distributions are roughly Gaussian. The `PrintHistogram` utility prints a simple 5-bin ASCII histogram for each feature. The output reveals that many features have more mass at one extreme — this is exactly the problem that the log transformation above helps to address.

{lang="swift",linenos=on}
~~~~~~~~
func printHistogram(title: String, data: [[Double]],
                    colIndex: Int, min: Double,
                    max: Double, numBins: Int) {
    var bins = [Int](repeating: 0, count: numBins)
    let range = max - min
    for row in data {
        let x = row[colIndex]
        let idx = Int((0.99 * (x - min) / range) * Double(numBins))
        let clampedIdx = Swift.max(0, Swift.min(numBins - 1, idx))
        bins[clampedIdx] += 1
    }
    print("\n\(title)")
    for (i, count) in bins.enumerated() {
        print("\(i)\t\(count)")
    }
}
~~~~~~~~

## Running the Example

```bash
cd source-code/anomaly-detection
swift run
```

The output includes the cross-validation error counts for each candidate epsilon, the final test-set metrics, and two inference examples:

{line-numbers=off}
~~~~~~~~
**** Best epsilon value = 0.25

 -- best epsilon       = 0.25
 -- test examples      = 97
 -- false positives    = 12.0
 -- true  positives    = 32.0
 -- false negatives    = 2.0
 -- true  negatives    = 51.0
 -- precision          = 0.727
 -- recall             = 0.941
 -- F1                 = 0.821

Using the trained model:
malignant result = true, benign result = false
~~~~~~~~

Results vary between runs because the train/validation/test split is randomised. The key correctness check is `malignant result = true, benign result = false`.

## Interpreting the Metrics

**Precision** (≈0.73) measures what fraction of examples flagged as anomalies were genuine anomalies. **Recall** (≈0.94) measures what fraction of all true anomalies the model caught. The **F1 score** is their harmonic mean and balances both concerns.

In a medical screening context high recall is often more important than high precision: it is worse to miss a cancer (false negative) than to follow up on a benign case unnecessarily (false positive). The model's high recall (catching ~94% of malignant cases) makes it useful as a first-pass screening tool.

Features that remain far from Gaussian even after transformation (for example "Bare Nuclei" in the Wisconsin data) should be investigated and potentially removed or transformed further. Andrew Ng's recommendation — taking the log of features or applying other monotonic transformations — is a good starting point.

## Summary

This chapter demonstrated how to port a Java Gaussian anomaly detection model to a standalone Swift command-line tool. The key ideas are:

- Fit a per-feature Gaussian distribution to "normal" training examples.
- Tune an epsilon cutoff using a cross-validation set.
- Evaluate precision, recall, and F1 on a held-out test set.
- Pre-process features toward a Gaussian shape to get better model performance.

The complete source is in `source-code/anomaly-detection/`.
