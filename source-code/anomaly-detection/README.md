# Anomaly Detection — Swift Command-Line Tool

A Swift port of the anomaly detection example from **Practical Artificial Intelligence Programming with Java** by Mark Watson.

Uses per-feature Gaussian distributions fit to "normal" (benign) training examples to flag anomalous (malignant) inputs from the [University of Wisconsin Breast Cancer dataset](https://archive.ics.uci.edu/ml/datasets/Breast+Cancer+Wisconsin+(Diagnostic)).

## Run

```bash
swift run
```

## Key Source Files

| File | Description |
|---|---|
| `Sources/AnomalyDetection/AnomalyDetection.swift` | Core model: Gaussian fitting, epsilon search, F1 evaluation |
| `Sources/AnomalyDetection/PrintHistogram.swift` | ASCII histogram utility |
| `Sources/AnomalyDetection/main.swift` | Data loading, preprocessing, training, inference |
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
