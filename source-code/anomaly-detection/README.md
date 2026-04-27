# Anomaly Detection — Example for Mark Watson's book "Artificial Intelligence Using Swift"

Book URI: https://leanpub.com/SwiftAI

You can read my book for free online at: https://leanpub.com/SwiftAI/read

A Swift port of the anomaly detection example from the book's Java edition. Uses per-feature **Gaussian distributions** fit to "normal" (benign) training examples to flag anomalous (malignant) inputs from the [University of Wisconsin Breast Cancer dataset](https://archive.ics.uci.edu/ml/datasets/Breast+Cancer+Wisconsin+(Diagnostic)).

**How it works:**

1. Load and preprocess the Wisconsin cancer dataset (699 examples, 9 features + label)
2. Split into training (benign-only) and test sets
3. Fit a Gaussian (μ, σ²) for each feature on the training set
4. Search for the optimal **epsilon** threshold that maximizes F1 score
5. Evaluate precision, recall, and F1 on the held-out test set
6. Classify two new examples as benign or malignant

## Run

    swift build
    swift run

## Key Source Files

| File | Description |
|---|---|
| `Sources/AnomalyDetection/AnomalyDetection.swift` | Core model: Gaussian fitting, epsilon search, F1 evaluation |
| `Sources/AnomalyDetection/PrintHistogram.swift` | ASCII histogram utility for visualizing feature distributions |
| `Sources/AnomalyDetection/main.swift` | Data loading, preprocessing, training, and inference demo |
| `Sources/AnomalyDetection/Resources/cleaned_wisconsin_cancer_data.csv` | Wisconsin cancer dataset (699 examples, 9 features + label) |

## Expected Output (approximate)

```
**** Best epsilon value = 0.28

 -- best epsilon       = 0.28
 -- test examples      = ~63
 -- precision          = ~1.0
 -- recall             = ~0.57
 -- F1                 = ~0.73

Using the trained model:
malignant result = true, benign result = false
```

## Book Cover Material, Copyright, and License

This example is released using the Apache 2 license.

Copyright 2022-2026 Mark Watson. All rights reserved.

## This Book is Licensed with Creative Commons Attribution CC BY Version 3 That Allows Reuse In Derived Works

You are free to:

- Share — copy and redistribute the material in any medium or format
- Adapt — remix, transform, and build upon the material
for any purpose, even commercially.

You are required to give appropriate credit in any derived works:

```text
This work is derived from all or part of "Artificial Intelligence Using Swift" by
Mark Watson. Source: https://leanpub.com/SwiftAI
```

Please visit the [author's website](http://markwatson.com).
