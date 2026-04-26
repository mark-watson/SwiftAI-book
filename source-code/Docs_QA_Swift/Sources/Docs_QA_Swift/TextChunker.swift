// TextChunker.swift — Sentence-aware text chunking using NLTokenizer
// Copyright 2022-2026 Mark Watson. All rights reserved.

import Foundation
import NaturalLanguage

// MARK: - String Utilities

extension String {
    /// Removes characters from the given set.
    func removeCharacters(from forbiddenChars: CharacterSet) -> String {
        let passed = self.unicodeScalars.filter {
            !forbiddenChars.contains($0)
        }
        return String(String.UnicodeScalarView(passed))
    }

    /// Strips common markup characters and collapses newlines.
    func plainText() -> String {
        return self
            .removeCharacters(
                from: CharacterSet(charactersIn: "\"`()%$#@[]{}<>"))
            .replacingOccurrences(of: "\n", with: " ")
    }
}

// MARK: - Sentence Segmentation

/// Splits text into individual sentences using Apple's NLTokenizer.
func segmentTextIntoSentences(text: String) -> [String] {
    let tokenizer = NLTokenizer(unit: .sentence)
    tokenizer.string = text
    return tokenizer.tokens(
        for: text.startIndex..<text.endIndex
    ).map { range in
        String(text[range])
    }
}

// MARK: - Chunking

/// Groups sentences into chunks that do not exceed `maxChunkSize`
/// characters. This preserves sentence boundaries so that chunks
/// contain complete sentences.
func segmentTextIntoChunks(text: String,
                           maxChunkSize: Int) -> [String] {
    let sentences = segmentTextIntoSentences(text: text)
    var chunks: [String] = []
    var currentChunk = ""
    var currentSize = 0

    for sentence in sentences {
        if currentSize + sentence.count < maxChunkSize {
            currentChunk += sentence
            currentSize += sentence.count
        } else {
            if !currentChunk.isEmpty {
                chunks.append(currentChunk)
            }
            currentChunk = sentence
            currentSize = sentence.count
        }
    }
    if !currentChunk.isEmpty {
        chunks.append(currentChunk)
    }
    return chunks
}
