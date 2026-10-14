import Foundation

public struct Passage: Sendable {
    public let topic: String
    public let text: String
}

public enum DocumentError: Error, CustomStringConvertible {
    case missingDataFile(URL)

    public var description: String {
        switch self {
        case .missingDataFile(let url):
            "Data file not found at \(url.path). Ensure ../data contains the required text files."
        }
    }
}

/// Loads ../data/*.txt; the file name ("sports", "health", ...) is the topic.
public enum Documents {
    public static let topics = ["chemistry", "economics", "health", "sports"]

    /// Chunks of whole sentences, up to about `maxWords` words, that never
    /// cross a paragraph boundary. Wikipedia style citation marks like [3]
    /// are removed.
    public static func passages(maxWords: Int = 60, minWords: Int = 8) throws -> [Passage] {
        var result: [Passage] = []
        for topic in topics {
            let url = Paths.sharedData.appending(path: "\(topic).txt")
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw DocumentError.missingDataFile(url)
            }
            let text = try String(contentsOf: url, encoding: .utf8)
            for paragraph in text.components(separatedBy: "\n\n") {
                let cleaned = paragraph
                    .replacingOccurrences(of: #"\[\d+\]"#, with: "", options: .regularExpression)
                    .split(whereSeparator: \.isWhitespace).joined(separator: " ")
                var chunk: [String] = []
                func flush() {
                    let joined = chunk.joined(separator: " ")
                    if joined.split(separator: " ").count >= minWords {
                        result.append(Passage(topic: topic, text: joined))
                    }
                    chunk = []
                }
                for sentence in splitSentences(cleaned) {
                    let words = (chunk + [sentence]).joined(separator: " ").split(separator: " ").count
                    if words > maxWords && !chunk.isEmpty { flush() }
                    chunk.append(sentence)
                }
                flush()
            }
        }
        return result
    }

    static func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { s, _, _, _ in
            if let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty { sentences.append(s) }
        }
        return sentences
    }

    /// Sentences, used as extra router training examples.
    public static func sentences(for topic: String) throws -> [String] {
        try passages(maxWords: 0, minWords: 5)
            .filter { $0.topic == topic }
            .map(\.text)
    }
}
