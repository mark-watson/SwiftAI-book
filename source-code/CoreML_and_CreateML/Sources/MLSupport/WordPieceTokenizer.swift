import Foundation

/// Minimal BERT uncased WordPiece tokenizer, enough for all-MiniLM-L6-v2.
///
/// Steps: lowercase, strip accents, split on whitespace and punctuation,
/// then greedy longest-match-first lookup where word-internal pieces carry
/// a "##" prefix.
public struct WordPieceTokenizer: Sendable {
    public let maxLength: Int
    private let vocab: [String: Int32]
    private let cls: Int32, sep: Int32, pad: Int32, unk: Int32

    public init(vocabURL: URL, maxLength: Int = 128) throws {
        let lines = try String(contentsOf: vocabURL, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
        var table: [String: Int32] = [:]
        for (i, token) in lines.enumerated() where !token.isEmpty {
            table[String(token)] = Int32(i)
        }
        vocab = table
        cls = table["[CLS]"]!
        sep = table["[SEP]"]!
        pad = table["[PAD]"]!
        unk = table["[UNK]"]!
        self.maxLength = maxLength
    }

    /// Returns padded token ids and the matching attention mask.
    public func encode(_ text: String) -> (ids: [Int32], mask: [Int32]) {
        var ids: [Int32] = [cls]
        for word in basicTokens(text) {
            ids.append(contentsOf: wordPiece(word))
            if ids.count >= maxLength - 1 { break }
        }
        ids = Array(ids.prefix(maxLength - 1)) + [sep]
        let realCount = ids.count
        ids += Array(repeating: pad, count: maxLength - realCount)
        let mask = (0..<maxLength).map { Int32($0 < realCount ? 1 : 0) }
        return (ids, mask)
    }

    private func basicTokens(_ text: String) -> [String] {
        let folded = text.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
        var tokens: [String] = []
        var current = ""
        for scalar in folded.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else if CharacterSet.punctuationCharacters.contains(scalar)
                        || CharacterSet.symbols.contains(scalar) {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(String(scalar))
            } else {
                current.unicodeScalars.append(scalar)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    private func wordPiece(_ word: String) -> [Int32] {
        let chars = Array(word)
        if chars.count > 100 { return [unk] }
        var pieces: [Int32] = []
        var start = 0
        while start < chars.count {
            var end = chars.count
            var match: Int32?
            while start < end {
                let piece = (start > 0 ? "##" : "") + String(chars[start..<end])
                if let id = vocab[piece] { match = id; break }
                end -= 1
            }
            guard let id = match else { return [unk] }
            pieces.append(id)
            start = end
        }
        return pieces
    }
}
