import Foundation

// A small JSON value type used for chat-completions payloads, responses,
// and the harness config. Integers and doubles are kept distinct so that
// values such as max_tokens round-trip as `32768`, not `32768.0`.
enum JSON: Codable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let i = try? c.decode(Int.self) { self = .int(i) }
        else if let d = try? c.decode(Double.self) { self = .double(d) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSON].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSON].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    // ---- Parsing / serialization ----

    static func parse(_ data: Data) throws -> JSON {
        try JSONDecoder().decode(JSON.self, from: data)
    }

    static func parse(_ text: String) throws -> JSON {
        try parse(Data(text.utf8))
    }

    func serialized(pretty: Bool = false) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = pretty
            ? [.withoutEscapingSlashes, .prettyPrinted, .sortedKeys]
            : [.withoutEscapingSlashes]
        guard let data = try? enc.encode(self) else { return "null" }
        return String(decoding: data, as: UTF8.self)
    }

    var data: Data { Data(serialized().utf8) }

    // ---- Accessors (all tolerant of the wrong shape) ----

    subscript(key: String) -> JSON? {
        get {
            if case .object(let o) = self { return o[key] }
            return nil
        }
        set {
            guard case .object(var o) = self else { return }
            o[key] = newValue
            self = .object(o)
        }
    }

    var string: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var int: Int? {
        switch self {
        case .int(let i): return i
        case .double(let d) where d == d.rounded(): return Int(d)
        default: return nil
        }
    }

    var double: Double? {
        switch self {
        case .double(let d): return d
        case .int(let i): return Double(i)
        default: return nil
        }
    }

    var bool: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    var array: [JSON]? {
        if case .array(let a) = self { return a }
        return nil
    }

    var object: [String: JSON]? {
        if case .object(let o) = self { return o }
        return nil
    }

    var isNull: Bool { self == .null }

    // Racket-style truthiness: everything except null and false is "set".
    var isTruthy: Bool {
        switch self {
        case .null, .bool(false): return false
        default: return true
        }
    }

    // A string, or a scalar rendered as text (tool arguments may arrive as
    // numbers when a model is sloppy about types).
    var textValue: String? {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return String(b)
        default: return nil
        }
    }
}

extension JSON: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByNilLiteral
{
    init(stringLiteral value: String) { self = .string(value) }
    init(integerLiteral value: Int) { self = .int(value) }
    init(floatLiteral value: Double) { self = .double(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(arrayLiteral elements: JSON...) { self = .array(elements) }
    init(dictionaryLiteral elements: (String, JSON)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, b in b }))
    }
    init(nilLiteral: ()) { self = .null }
}

// Error type used throughout the harness: a message, printed as-is.
struct AgentError: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}
