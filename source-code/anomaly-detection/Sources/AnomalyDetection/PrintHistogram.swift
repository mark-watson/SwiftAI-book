// PrintHistogram.swift
// Swift port of the Java PrintHistogram utility class.

import Foundation

/// Prints a simple text histogram for one feature column of a 2-D data array.
///
/// - Parameters:
///   - title:    Label printed above the histogram.
///   - data:     2-D array of shape `[N][numFeatures]`.
///   - colIndex: Column index to histogram.
///   - min:      Expected minimum value of the feature.
///   - max:      Expected maximum value of the feature.
///   - numBins:  Number of histogram buckets.
func printHistogram(title: String,
                    data: [[Double]],
                    colIndex: Int,
                    min: Double,
                    max: Double,
                    numBins: Int) {
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
