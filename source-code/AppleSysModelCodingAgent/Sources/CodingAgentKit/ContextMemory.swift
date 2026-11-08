import Foundation
import NaturalLanguage

// In-memory retrieval (RAG) for the on-device model's small context window.
//
// The on-device model sees about 8,192 tokens: instructions, tool schemas,
// the prompt, every tool call and result made during the turn, and the reply
// all share that window. A conversation of any length, plus the files the
// agent reads, does not fit. So nothing is thrown away; instead everything is
// indexed here, and each request carries only
//
//   1. the most recent turns, compressed, that fit a token budget, and
//   2. the chunks of older material most relevant to the current request,
//
// assembled by ContextBuilder (ContextBuilder.swift). The model can also query
// the store itself through the search_memory tool.
//
// What is indexed:
//   - every user request and assistant reply           (kind .user / .assistant)
//   - every tool result, in full, before it is
//     truncated for the model                          (kind .tool / .file)
//   - skills loaded with /<skill-name>                  (kind .skill)
//   - /compact summaries                                (kind .summary)
//   - project source files indexed with /index          (kind .project)
//
// Retrieval is hybrid:
//   - lexical: Okapi BM25 over identifier-aware terms (camelCase and
//     snake_case are split, so "parseToolCalls" matches "tool calls"),
//   - semantic: cosine similarity of NaturalLanguage sentence embeddings
//     (on-device; skipped when the embedding asset is unavailable),
//   - a recency bonus that decays with the number of turns since the chunk,
//   - then Maximal Marginal Relevance (MMR) re-ranking so the few chunks that
//     fit are not near-duplicates of each other.
//
// All of it lives in process memory and is rebuilt per session.

enum MemoryKind: String, CaseIterable, Sendable {
    case user, assistant, tool, file, skill, summary, project
}

struct MemoryChunk: Sendable {
    let id: Int
    let kind: MemoryKind
    /// Human-readable origin, e.g. "turn 3 · read_file Sources/a.swift:1-40".
    let source: String
    /// Re-indexing under the same key replaces the older chunks (a file that
    /// was read again, or edited, must not be retrieved in its stale form).
    let key: String?
    let text: String
    let turn: Int
    let termFreq: [String: Int]
    let termCount: Int
    let vector: [Float]?
}

struct MemoryHit: Sendable {
    let chunk: MemoryChunk
    let score: Double
}

// ---------------------------------------------------------------------------
// Terms

enum MemoryTokenizer {
    static let stopwords: Set<String> = [
        "the", "and", "for", "are", "but", "not", "you", "all", "any", "can", "had", "her", "was",
        "one", "our", "out", "has", "have", "this", "that", "with", "from", "they", "will", "would",
        "there", "their", "what", "when", "which", "while", "into", "then", "than", "them", "these",
        "those", "some", "such", "only", "also", "just", "very", "been", "being", "were", "your",
        "about", "should", "could", "does", "did", "doing", "how", "why", "where", "who", "its",
        "let", "var", "self", "return", "func", "import", "def", "true", "false", "nil", "null",
        "please", "want", "need", "make", "like", "use", "using",
    ]

    /// Lower-cased terms of `text`. Identifiers contribute themselves and
    /// their camelCase / snake_case parts; plurals are folded.
    static func terms(_ text: String) -> [String] {
        var out: [String] = []
        var word = ""
        func flush() {
            defer { word = "" }
            guard word.count >= 2 else { return }
            let parts = splitIdentifier(word)
            if parts.count > 1 { add(word.lowercased()) }
            for p in parts { add(p.lowercased()) }
        }
        func add(_ t: String) {
            guard t.count >= 2, t.count <= 40, !stopwords.contains(t),
                  !t.allSatisfy(\.isNumber) else { return }
            out.append(stem(t))
        }
        for c in text {
            if c.isLetter || c.isNumber || c == "_" { word.append(c) } else { flush() }
        }
        flush()
        return out
    }

    /// "parseToolCalls" -> [parse, Tool, Calls]; "make_check" -> [make, check];
    /// "HTTPServer" -> [HTTP, Server].
    static func splitIdentifier(_ w: String) -> [String] {
        var parts: [String] = []
        for piece in w.split(separator: "_") {
            let chars = Array(piece)
            var cur = ""
            for (i, c) in chars.enumerated() {
                let prev: Character? = i > 0 ? chars[i - 1] : nil
                let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
                let boundary = c.isUppercase && prev != nil
                    && (prev!.isLowercase || prev!.isNumber || (prev!.isUppercase && (next?.isLowercase ?? false)))
                if boundary, !cur.isEmpty { parts.append(cur); cur = "" }
                cur.append(c)
            }
            if !cur.isEmpty { parts.append(cur) }
        }
        return parts
    }

    static func stem(_ t: String) -> String {
        if t.count > 4 && t.hasSuffix("ies") { return String(t.dropLast(3)) + "y" }
        if t.count > 3 && t.hasSuffix("s") && !t.hasSuffix("ss") && !t.hasSuffix("us") {
            return String(t.dropLast())
        }
        return t
    }
}

// ---------------------------------------------------------------------------
// Embeddings (NaturalLanguage, on-device)

enum MemoryEmbedder {
    /// Text past this length adds cost but little signal to a sentence vector.
    static let maxChars = 1000
    /// Set to false to run purely lexical retrieval (tests, or a machine
    /// without the embedding asset).
    nonisolated(unsafe) static var enabled = true

    private static let lock = NSLock()
    nonisolated(unsafe) private static let model: NLEmbedding? = NLEmbedding.sentenceEmbedding(for: .english)

    static var available: Bool { enabled && model != nil }

    /// Unit-length vector, or nil when embeddings are unavailable.
    static func vector(_ text: String) -> [Float]? {
        guard enabled, let model else { return nil }
        let t = String(text.prefix(maxChars))
        guard !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        lock.lock()
        let v = model.vector(for: t)
        lock.unlock()
        guard let v, !v.isEmpty else { return nil }
        let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return nil }
        return v.map { Float($0 / norm) }
    }

    static func cosine(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count else { return 0 }
        var s: Float = 0
        for i in 0..<a.count { s += a[i] * b[i] }
        return Double(s)
    }
}

// ---------------------------------------------------------------------------
// Chunking

enum MemoryChunker {
    struct Piece { let text: String; let firstLine: Int; let lastLine: Int }

    /// Splits text into pieces of at most `maxChars`, on line boundaries where
    /// possible, repeating up to `overlapLines` lines between neighbours so a
    /// function split across two pieces is still recognisable in each.
    static func split(_ text: String, maxChars: Int = 900, overlapLines: Int = 2) -> [Piece] {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last == "" { lines.removeLast() }
        // Hard-wrap single lines that are longer than a whole piece.
        var wrapped: [(String, Int)] = []
        for (i, l) in lines.enumerated() {
            if l.count <= maxChars { wrapped.append((l, i + 1)); continue }
            var rest = Substring(l)
            while !rest.isEmpty {
                var cut = rest.index(rest.startIndex, offsetBy: min(maxChars, rest.count))
                if cut < rest.endIndex, let space = rest[..<cut].lastIndex(of: " "),
                   rest.distance(from: rest.startIndex, to: space) > maxChars / 2 {
                    cut = rest.index(after: space)
                }
                wrapped.append((String(rest[..<cut]), i + 1))
                rest = rest[cut...]
            }
        }
        var pieces: [Piece] = []
        var start = 0
        while start < wrapped.count {
            var end = start
            var size = 0
            while end < wrapped.count, size == 0 || size + wrapped[end].0.count + 1 <= maxChars {
                size += wrapped[end].0.count + 1
                end += 1
            }
            let body = wrapped[start..<end].map(\.0).joined(separator: "\n")
            pieces.append(Piece(text: body, firstLine: wrapped[start].1, lastLine: wrapped[end - 1].1))
            if end >= wrapped.count { break }
            // Overlap, but always advance, and never overlap more than a third.
            var back = 0
            var overlapSize = 0
            while back < overlapLines, end - back - 1 > start,
                  overlapSize + wrapped[end - back - 1].0.count < maxChars / 3 {
                overlapSize += wrapped[end - back - 1].0.count
                back += 1
            }
            start = end - back
        }
        return pieces
    }
}

// ---------------------------------------------------------------------------
// The store

final class MemoryStore: @unchecked Sendable {
    static let shared = MemoryStore()

    // BM25 parameters (the usual defaults).
    static let k1 = 1.2
    static let b = 0.75
    /// Weight of lexical vs. semantic similarity when both are available.
    static let lexicalWeight = 0.6
    /// Bonus for recent chunks: recencyWeight * exp(-turnsAgo / recencyTurns).
    static let recencyWeight = 0.15
    static let recencyTurns = 6.0
    /// MMR trade-off: 1.0 is pure relevance, 0.0 pure diversity.
    static let mmrLambda = 0.7
    /// Chunks below this relevance are never returned, however recent.
    static let minRelevance = 0.08
    static let chunkChars = 900

    private let lock = NSLock()
    private var chunks: [MemoryChunk] = []
    private var docFreq: [String: Int] = [:]
    private var totalTerms = 0
    private var nextID = 1
    private var _turn = 0

    /// The agent's turn counter; new chunks are stamped with it.
    var currentTurn: Int {
        get { lock.lock(); defer { lock.unlock() }; return _turn }
        set { lock.lock(); _turn = newValue; lock.unlock() }
    }

    var count: Int { lock.lock(); defer { lock.unlock() }; return chunks.count }

    // ---- Writing ----

    /// Chunks, embeds, and indexes `text`. Returns the number of chunks added.
    @discardableResult
    func add(_ text: String, kind: MemoryKind, source: String, key: String? = nil,
             turn: Int? = nil, lineNumbers: Bool = false) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let key { remove(key: key) }
        guard trimmed.count >= 12 else { return 0 }
        let t = turn ?? currentTurn
        // The expensive part (embedding) runs outside the lock.
        let pieces = MemoryChunker.split(trimmed, maxChars: Self.chunkChars)
        let prepared: [(String, String, [String: Int], Int, [Float]?)] = pieces.map { p in
            let src = lineNumbers && pieces.count > 1 ? "\(source):\(p.firstLine)-\(p.lastLine)" : source
            let terms = MemoryTokenizer.terms(src + " " + p.text)
            var tf: [String: Int] = [:]
            for term in terms { tf[term, default: 0] += 1 }
            return (src, p.text, tf, terms.count, MemoryEmbedder.vector(p.text))
        }
        lock.lock(); defer { lock.unlock() }
        var added = 0
        for (src, body, tf, n, vec) in prepared {
            // The same text already indexed (a file read twice, a repeated
            // grep) would only crowd out other results.
            if chunks.contains(where: { $0.kind == kind && $0.text == body }) { continue }
            chunks.append(MemoryChunk(id: nextID, kind: kind, source: src, key: key, text: body,
                                      turn: t, termFreq: tf, termCount: n, vector: vec))
            nextID += 1
            totalTerms += n
            for term in tf.keys { docFreq[term, default: 0] += 1 }
            added += 1
        }
        return added
    }

    func remove(key: String) {
        lock.lock(); defer { lock.unlock() }
        removeLocked { $0.key == key }
    }

    /// Clears the store. Project files indexed with /index survive a
    /// conversation reset unless `keepProject` is false.
    func clear(keepProject: Bool = true) {
        lock.lock(); defer { lock.unlock() }
        if keepProject { removeLocked { $0.kind != .project } } else {
            chunks = []; docFreq = [:]; totalTerms = 0
        }
        _turn = 0
    }

    private func removeLocked(_ pred: (MemoryChunk) -> Bool) {
        let (gone, kept) = chunks.reduce(into: ([MemoryChunk](), [MemoryChunk]())) {
            if pred($1) { $0.0.append($1) } else { $0.1.append($1) }
        }
        guard !gone.isEmpty else { return }
        chunks = kept
        for c in gone {
            totalTerms -= c.termCount
            for term in c.termFreq.keys {
                let n = (docFreq[term] ?? 1) - 1
                docFreq[term] = n > 0 ? n : nil
            }
        }
    }

    // ---- Reading ----

    struct Stats { let chunks: Int; let chars: Int; let byKind: [MemoryKind: Int]; let embedded: Int }

    var stats: Stats {
        lock.lock(); defer { lock.unlock() }
        var byKind: [MemoryKind: Int] = [:]
        for c in chunks { byKind[c.kind, default: 0] += 1 }
        return Stats(chunks: chunks.count, chars: chunks.reduce(0) { $0 + $1.text.count },
                     byKind: byKind, embedded: chunks.filter { $0.vector != nil }.count)
    }

    /// The `limit` chunks most relevant to `query`, best first. `exclude`
    /// drops chunks the caller already shows the model (e.g. the turns in the
    /// recent-conversation window).
    func search(_ query: String, limit: Int = 6,
                exclude: (MemoryChunk) -> Bool = { _ in false }) -> [MemoryHit] {
        let qTerms = Array(Set(MemoryTokenizer.terms(query)))
        let qVec = MemoryEmbedder.vector(query)
        lock.lock()
        let snapshot = chunks
        let df = docFreq
        let n = Double(max(chunks.count, 1))
        let avgLen = max(Double(totalTerms) / n, 1)
        let now = _turn
        lock.unlock()

        let candidates = snapshot.filter { !exclude($0) }
        guard !candidates.isEmpty, !qTerms.isEmpty || qVec != nil else { return [] }

        // Lexical score (BM25), normalised by the best candidate.
        let idf: [String: Double] = Dictionary(uniqueKeysWithValues: qTerms.map { t in
            let d = Double(df[t] ?? 0)
            return (t, log(1 + (n - d + 0.5) / (d + 0.5)))
        })
        let bm25 = candidates.map { c -> Double in
            var s = 0.0
            let len = Double(max(c.termCount, 1))
            for t in qTerms {
                guard let tf = c.termFreq[t] else { continue }
                let f = Double(tf)
                s += idf[t]! * f * (Self.k1 + 1) / (f + Self.k1 * (1 - Self.b + Self.b * len / avgLen))
            }
            return s
        }
        let maxBM = max(bm25.max() ?? 0, 1e-9)

        var scored: [MemoryHit] = []
        for (i, c) in candidates.enumerated() {
            let lexical = bm25[i] / maxBM
            var relevance = lexical
            if let q = qVec, let v = c.vector {
                // Sentence vectors of unrelated text still score ~0.2-0.3, so
                // only the part above that floor counts.
                let semantic = max(0, (MemoryEmbedder.cosine(q, v) - 0.25) / 0.75)
                relevance = Self.lexicalWeight * lexical + (1 - Self.lexicalWeight) * semantic
            }
            guard relevance >= Self.minRelevance else { continue }
            let age = Double(max(now - c.turn, 0))
            let score = relevance + Self.recencyWeight * exp(-age / Self.recencyTurns)
            scored.append(MemoryHit(chunk: c, score: score))
        }
        scored.sort { $0.score > $1.score }
        return Self.mmr(Array(scored.prefix(limit * 4)), limit: limit)
    }

    /// Maximal Marginal Relevance: greedily pick the hit with the best
    /// lambda * score - (1 - lambda) * (similarity to anything already picked).
    static func mmr(_ hits: [MemoryHit], limit: Int) -> [MemoryHit] {
        var pool = hits
        var picked: [MemoryHit] = []
        let top = max(hits.first?.score ?? 1, 1e-9)
        while !pool.isEmpty && picked.count < limit {
            var best = 0
            var bestValue = -Double.infinity
            for (i, h) in pool.enumerated() {
                let redundancy = picked.map { similarity(h.chunk, $0.chunk) }.max() ?? 0
                let value = mmrLambda * (h.score / top) - (1 - mmrLambda) * redundancy
                if value > bestValue { bestValue = value; best = i }
            }
            picked.append(pool.remove(at: best))
        }
        return picked
    }

    static func similarity(_ a: MemoryChunk, _ b: MemoryChunk) -> Double {
        if let x = a.vector, let y = b.vector { return max(0, MemoryEmbedder.cosine(x, y)) }
        let sa = Set(a.termFreq.keys), sb = Set(b.termFreq.keys)
        let union = sa.union(sb).count
        return union == 0 ? 0 : Double(sa.intersection(sb).count) / Double(union)
    }

    /// Hits as prompt text, adding whole chunks while they fit `maxChars`.
    static func render(_ hits: [MemoryHit], maxChars: Int) -> (text: String, used: Int) {
        var parts: [String] = []
        var size = 0
        for h in hits {
            let block = "[M\(parts.count + 1)] \(h.chunk.source)\n\(h.chunk.text)"
            if size + block.count + 2 > maxChars {
                // A partial chunk is still useful when nothing else fits.
                if parts.isEmpty, maxChars > 300 {
                    parts.append(String(block.prefix(maxChars - 20)) + "\n…")
                }
                break
            }
            parts.append(block)
            size += block.count + 2
        }
        return (parts.joined(separator: "\n\n"), parts.count)
    }
}

// ---------------------------------------------------------------------------
// What gets indexed from tool calls

extension MemoryStore {
    /// Indexes the complete result of one tool call, before it is truncated
    /// for the model.
    func ingestToolResult(name: String, argsJSON: String, result: String) {
        let args = (try? JSON.parse(argsJSON)) ?? [:]
        let turn = currentTurn
        switch name {
        case "search_memory":
            return  // already in memory
        case "read_file":
            guard let path = args["path"]?.string, !result.hasPrefix("Error"),
                  !result.hasPrefix("refusing") else { return }
            // A whole-file read replaces any older copy of the file; a paged
            // read is keyed by its range.
            let offset = args["offset"]?.int ?? 1
            let paged = args["offset"] != nil || args["limit"] != nil || result.contains("call read_file with offset=")
            add(result, kind: .file, source: "turn \(turn) · file \(path)",
                key: paged ? "file:\(path)@\(offset)" : "file:\(path)", lineNumbers: offset == 1)
        case "propose_edit":
            let path = args["path"]?.string ?? "?"
            if result.hasPrefix("applied"), let new = args["new"]?.string {
                // The file changed: drop stale copies and index the new text.
                remove(key: "file:\(path)")
                add(new, kind: .file, source: "turn \(turn) · file \(path) (after edit)",
                    key: "file:\(path)", lineNumbers: true)
            }
            add("propose_edit \(path): \(result)", kind: .tool, source: "turn \(turn) · propose_edit \(path)")
        default:
            let label = Self.describeCall(name, args)
            add(result, kind: .tool, source: "turn \(turn) · \(label)", key: "tool:\(label)")
        }
    }

    static func describeCall(_ name: String, _ args: JSON) -> String {
        let main = ["path", "pattern", "command", "url", "query"].compactMap { args[$0]?.string }
        let joined = main.joined(separator: " ")
        return joined.isEmpty ? name : "\(name) \(joined.count > 80 ? String(joined.prefix(77)) + "…" : joined)"
    }
}
