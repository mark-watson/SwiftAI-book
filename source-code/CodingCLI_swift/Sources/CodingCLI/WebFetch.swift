import Foundation

// fetch_url tool backend: download a web page and reduce its HTML to
// readable plain text for the model.
//
// Tool handlers are synchronous, so the URLSession request is bridged with a
// semaphore. Output is capped so one large page cannot flood the context.

enum WebFetch {
    static let maxChars = 20000
    static let timeout: TimeInterval = 20

    private final class ResultBox: @unchecked Sendable {
        var data: Data?
        var response: URLResponse?
        var error: Error?
    }

    static func fetch(_ urlString: String) -> String {
        var s = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            s = "https://" + s
        }
        guard let url = URL(string: s), let host = url.host, !host.isEmpty else {
            return "Error: invalid URL: \(urlString)"
        }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.setValue("Mozilla/5.0 (Macintosh) CodingCLI/1.0", forHTTPHeaderField: "User-Agent")
        req.setValue("text/html,text/plain;q=0.9,*/*;q=0.5", forHTTPHeaderField: "Accept")

        let box = ResultBox()
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { data, response, error in
            box.data = data
            box.response = response
            box.error = error
            sem.signal()
        }.resume()
        sem.wait()

        if let error = box.error {
            return "Error fetching \(s): \(error.localizedDescription)"
        }
        let http = box.response as? HTTPURLResponse
        if let code = http?.statusCode, !(200..<300).contains(code) {
            return "Error fetching \(s): HTTP \(code)"
        }
        let data = box.data ?? Data()
        let contentType = (http?.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        let raw = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let looksHTML = contentType.contains("html")
            || raw.prefix(1000).lowercased().contains("<html")
        let text = looksHTML ? htmlToText(raw) : raw
        let finalURL = box.response?.url?.absoluteString ?? s
        return "[Contents of \(finalURL)]\n" + Tools.truncate(text, maxChars)
    }

    // Regex-based HTML -> text: drop non-content elements, turn block-level
    // tags into newlines, strip remaining tags, decode entities, and collapse
    // whitespace. Good enough for reading a page; not a full HTML parser.
    static func htmlToText(_ html: String) -> String {
        var s = html
        func replace(_ pattern: String, _ with: String) {
            s = s.replacingOccurrences(of: pattern, with: with,
                                       options: [.regularExpression, .caseInsensitive])
        }
        replace("<!--[\\s\\S]*?-->", " ")
        for tag in ["script", "style", "noscript", "svg", "head", "template", "iframe"] {
            replace("<\(tag)\\b[^>]*>[\\s\\S]*?</\(tag)\\s*>", " ")
        }
        replace("<(br|hr)\\b[^>]*>", "\n")
        replace("</?(p|div|section|article|header|footer|nav|main|aside|li|ul|ol|tr|table|h[1-6]|blockquote|pre|dd|dt)\\b[^>]*>", "\n")
        replace("<[^>]+>", " ")
        s = decodeEntities(s)
        replace("[ \\t\\u00a0]+", " ")
        replace(" *\\n *", "\n")
        replace("\\n{3,}", "\n\n")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "mdash": "—", "ndash": "–", "hellip": "…", "copy": "©", "reg": "®",
        "rsquo": "’", "lsquo": "‘", "rdquo": "”", "ldquo": "“", "trade": "™",
    ]

    static func decodeEntities(_ s: String) -> String {
        let re = try! NSRegularExpression(pattern: "&(#[xX]?[0-9a-fA-F]+|[a-zA-Z]+);")
        let ns = s as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let body = ns.substring(with: m.range(at: 1))
            var rep: String?
            if body.hasPrefix("#") {
                let hex = body.dropFirst().lowercased().hasPrefix("x")
                let digits = body.dropFirst(hex ? 2 : 1)
                if let v = UInt32(digits, radix: hex ? 16 : 10), let u = Unicode.Scalar(v) {
                    rep = String(Character(u))
                }
            } else {
                rep = namedEntities[body.lowercased()]
            }
            out += rep ?? ns.substring(with: m.range)
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }
}
