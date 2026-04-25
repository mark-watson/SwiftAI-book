// BM25.swift
// A self-contained implementation of the BM25 Okapi ranking function.
//
// BM25 is a probabilistic retrieval model that scores documents
// against a query by considering term frequency, inverse document
// frequency, and document length normalization.

import Foundation

// MARK: - BM25 Index

/// Holds precomputed statistics for the BM25 ranking algorithm.
struct BM25Index {
    /// Number of documents each term appears in.
    let docFreqs: [String: Int]
    /// Number of tokens in each document.
    let docLengths: [Int]
    /// Average document length across the corpus.
    let avgDocLength: Double
    /// Total number of documents in the corpus.
    let corpusSize: Int
    /// The tokenized corpus (array of token arrays).
    let corpus: [[String]]
    /// Term-frequency saturation parameter (default 1.5).
    let k1: Double
    /// Length normalization parameter (default 0.75).
    let b: Double

    /// Builds a BM25 index from pre-tokenized documents.
    init(
        tokenizedCorpus: [[String]],
        k1: Double = 1.5,
        b: Double = 0.75
    ) {
        self.corpus = tokenizedCorpus
        self.k1 = k1
        self.b = b
        self.corpusSize = tokenizedCorpus.count

        // Compute per-document lengths.
        self.docLengths = tokenizedCorpus.map { $0.count }

        // Average document length.
        let totalLength = docLengths.reduce(0, +)
        self.avgDocLength = corpusSize > 0
            ? Double(totalLength) / Double(corpusSize) : 1.0

        // Document frequencies: how many docs contain each term?
        var freqs: [String: Int] = [:]
        for doc in tokenizedCorpus {
            let uniqueTerms = Set(doc)
            for term in uniqueTerms {
                freqs[term, default: 0] += 1
            }
        }
        self.docFreqs = freqs
    }

    // MARK: - IDF

    /// Computes the Inverse Document Frequency for a term.
    func idf(for term: String) -> Double {
        let df = Double(docFreqs[term] ?? 0)
        let n = Double(corpusSize)
        return log10((n - df + 0.5) / (df + 0.5))
    }

    // MARK: - Scoring

    /// BM25 score for document at `docIndex` given `queryTokens`.
    func score(docIndex: Int, queryTokens: [String]) -> Double {
        let doc = corpus[docIndex]
        let docLength = Double(docLengths[docIndex])
        var score = 0.0

        for term in queryTokens {
            let tf = Double(doc.filter { $0 == term }.count)
            let termIDF = idf(for: term)
            let numerator = tf * (k1 + 1)
            let denominator = tf + k1 *
                (1 - b + b * (docLength / avgDocLength))
            score += termIDF * (numerator / denominator)
        }
        return score
    }

    // MARK: - Top-N Retrieval

    /// Returns the top `n` tokenized documents ranked by BM25,
    /// omitting any document whose score is at or below `minScore`.
    func topN(
        _ n: Int,
        for queryTokens: [String],
        minScore: Double = 0.0
    ) -> [[String]] {
        let scored = corpus.indices.map { i in
            (score: score(docIndex: i, queryTokens: queryTokens),
             index: i)
        }
        let sorted = scored
            .filter { $0.score > minScore }
            .sorted { $0.score > $1.score }
        let topK = sorted.prefix(n)
        return topK.map { corpus[$0.index] }
    }
}
