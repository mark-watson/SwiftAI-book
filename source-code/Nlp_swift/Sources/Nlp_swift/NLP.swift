// NLP.swift — NLP utility functions using Apple's NaturalLanguage framework
// Copyright 2022-2026 Mark Watson. All rights reserved.

import NaturalLanguage

/// Extracts named entities (person, place, organization) from the given text.
///
/// Uses `NLTagger` with the `.nameType` scheme to identify named entities.
/// Returns an array of tuples where each tuple contains the entity text and
/// its tag (e.g. "PersonalName", "PlaceName", "OrganizationName").
public func getEntities(for text: String) -> [(String, String)] {
    let tagger = NLTagger(tagSchemes: [.nameType])
    tagger.string = text
    let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
    var results: [(String, String)] = []
    tagger.enumerateTags(
        in: text.startIndex..<text.endIndex,
        unit: .word,
        scheme: .nameType,
        options: options
    ) { tag, range in
        if let tag = tag {
            results.append((String(text[range]), tag.rawValue))
        }
        return true
    }
    return results
}

/// Extracts lemmas (base word forms) for each word in the given text.
///
/// Uses `NLTagger` with the `.lemma` scheme. For example, "went" yields
/// the lemma "go", and "representatives" yields "representative".
public func getLemmas(for text: String) -> [(String, String)] {
    let tagger = NLTagger(tagSchemes: [.lemma])
    tagger.string = text
    let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace]
    var results: [(String, String)] = []
    tagger.enumerateTags(
        in: text.startIndex..<text.endIndex,
        unit: .word,
        scheme: .lemma,
        options: options
    ) { tag, range in
        let word = String(text[range])
        let lemma = tag?.rawValue ?? word
        results.append((word, lemma))
        return true
    }
    return results
}

/// Detects the dominant language of the given text.
///
/// Uses `NLLanguageRecognizer` which supports over 50 languages.
public func detectLanguage(for text: String) -> String {
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(text)
    guard let language = recognizer.dominantLanguage else {
        return "Unknown"
    }
    return language.rawValue
}

/// Returns the top language hypotheses with confidence scores.
///
/// Useful when text contains multiple languages or when the dominant
/// language detection is uncertain.
public func languageHypotheses(for text: String, maxCount: Int = 5) -> [(String, Double)] {
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(text)
    let hypotheses = recognizer.languageHypotheses(withMaximum: maxCount)
    return hypotheses
        .map { ($0.key.rawValue, $0.value) }
        .sorted { $0.1 > $1.1 }
}

/// Analyzes the sentiment of the given text.
///
/// Returns a score between -1.0 (very negative) and 1.0 (very positive).
/// A score near 0.0 indicates neutral sentiment.
public func analyzeSentiment(for text: String) -> Double {
    let tagger = NLTagger(tagSchemes: [.sentimentScore])
    tagger.string = text
    let (tag, _) = tagger.tag(at: text.startIndex, unit: .paragraph,
                               scheme: .sentimentScore)
    if let tag = tag, let score = Double(tag.rawValue) {
        return score
    }
    return 0.0
}

/// Performs sentence-level sentiment analysis on each sentence in the text.
///
/// Splits the text into sentences using `NLTokenizer`, then analyzes
/// each sentence individually. Returns an array of (sentence, score) tuples.
public func sentimentBySentence(for text: String) -> [(String, Double)] {
    let tokenizer = NLTokenizer(unit: .sentence)
    tokenizer.string = text
    var results: [(String, Double)] = []
    tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
        let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !sentence.isEmpty {
            let score = analyzeSentiment(for: sentence)
            results.append((sentence, score))
        }
        return true
    }
    return results
}

/// Finds the nearest neighbors of a word using Apple's built-in word embeddings.
///
/// Apple provides pre-trained word embeddings for English and other languages
/// that can be used to find semantically similar words.
public func findSimilarWords(for word: String, maxResults: Int = 5) -> [(String, Double)] {
    guard let embedding = NLEmbedding.wordEmbedding(for: .english) else {
        return []
    }
    var results: [(String, Double)] = []
    embedding.enumerateNeighbors(for: word, maximumCount: maxResults) { neighbor, distance in
        results.append((neighbor, distance))
        return true
    }
    return results
}
