// main.swift — NLP example demonstrating Apple's NaturalLanguage framework
// Copyright 2022-2026 Mark Watson. All rights reserved.

import Foundation

// MARK: - Sample Text

let quote = """
    President George Bush went to Mexico with IBM representatives. \
    The technology sector saw significant growth last quarter. \
    Apple Inc. reported strong earnings from their Cupertino headquarters. \
    Steve Jobs founded Apple in his garage in Los Altos, California.
    """

// MARK: - Named Entity Recognition

print("=== Named Entity Recognition ===\n")
let entities = getEntities(for: quote)
let namedEntities = entities.filter { $0.1 != "OtherWord" }
for (word, tag) in namedEntities {
    print("  \(word) → \(tag)")
}

// MARK: - Lemmatization

print("\n=== Lemmatization (showing changed forms) ===\n")
let lemmas = getLemmas(for: quote)
let changedLemmas = lemmas.filter { $0.0.lowercased() != $0.1.lowercased() }
for (word, lemma) in changedLemmas {
    print("  \(word) → \(lemma)")
}

// MARK: - Language Detection

print("\n=== Language Detection ===\n")
let samples = [
    "The quick brown fox jumps over the lazy dog.",
    "Le renard brun rapide saute par-dessus le chien paresseux.",
    "Der schnelle braune Fuchs springt über den faulen Hund.",
    "El rápido zorro marrón salta sobre el perro perezoso."
]
for sample in samples {
    let lang = detectLanguage(for: sample)
    let preview = String(sample.prefix(50))
    print("  \"\(preview)...\" → \(lang)")
}

// MARK: - Sentiment Analysis

print("\n=== Sentiment Analysis ===\n")
let sentimentSamples = [
    "I absolutely love this product! It's amazing and works perfectly.",
    "This is the worst experience I have ever had. Terrible service.",
    "The meeting is scheduled for 3pm tomorrow in the conference room.",
    "The weather today is partly cloudy with a chance of rain."
]
for sample in sentimentSamples {
    let score = analyzeSentiment(for: sample)
    let label = score > 0.1 ? "positive" : (score < -0.1 ? "negative" : "neutral")
    let preview = String(sample.prefix(55))
    print("  \"\(preview)...\"")
    print("    score: \(String(format: "%.2f", score)) (\(label))\n")
}

// MARK: - Sentence-Level Sentiment

print("=== Sentence-Level Sentiment ===\n")
let mixedText = """
    The hotel room was beautiful and spacious. \
    However, the service was disappointing and slow. \
    The food at the restaurant was absolutely delicious. \
    I would not recommend the spa facilities.
    """
let sentenceSentiments = sentimentBySentence(for: mixedText)
for (sentence, score) in sentenceSentiments {
    let label = score > 0.1 ? "positive" : (score < -0.1 ? "negative" : "neutral")
    let preview = String(sentence.prefix(50))
    print("  \"\(preview)...\" → \(String(format: "%.2f", score)) (\(label))")
}

// MARK: - Word Embeddings

print("\n=== Word Embeddings (similar words) ===\n")
let queryWords = ["king", "computer", "happy"]
for word in queryWords {
    let similar = findSimilarWords(for: word, maxResults: 5)
    if similar.isEmpty {
        print("  \(word): (no embedding available)")
    } else {
        let neighbors = similar.map { "\($0.0) (\(String(format: "%.2f", $0.1)))" }
        print("  \(word) → \(neighbors.joined(separator: ", "))")
    }
}
