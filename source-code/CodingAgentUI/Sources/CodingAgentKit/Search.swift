import Foundation

// Brave Search and Exa AI search backends.
// Each returns a list of (url, title, description/highlight).

struct SearchResult {
    let url: String
    let title: String
    let snippet: String
}

enum Search {
    static let exaEndpoint = "https://api.exa.ai/search"

    static func apiKey(_ env: String) throws -> String {
        guard let k = ProcessInfo.processInfo.environment[env], !k.isEmpty else {
            throw AgentError("\(env) environment variable not set")
        }
        return k
    }

    static func brave(_ query: String, count: Int = 5) async throws -> [SearchResult] {
        let key = try apiKey("BRAVE_SEARCH_API_KEY")
        var comps = URLComponents(string: "https://api.search.brave.com/res/v1/web/search")!
        comps.queryItems = [URLQueryItem(name: "q", value: query),
                            URLQueryItem(name: "count", value: String(count))]
        var req = URLRequest(url: comps.url!)
        req.setValue(key, forHTTPHeaderField: "X-Subscription-Token")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (raw, _) = try await URLSession.shared.data(for: req)
        let data = try JSON.parse(raw)
        return (data["web"]?["results"]?.array ?? []).map {
            SearchResult(url: $0["url"]?.string ?? "", title: $0["title"]?.string ?? "",
                         snippet: $0["description"]?.string ?? "")
        }
    }

    static func exa(_ query: String, count: Int = 5) async throws -> [SearchResult] {
        let key = try apiKey("EXA_SEARCH_API_KEY")
        var req = URLRequest(url: URL(string: exaEndpoint)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let payload: JSON = ["query": .string(query), "type": "auto", "numResults": .int(count),
                             "contents": ["highlights": true]]
        req.httpBody = payload.data
        let (raw, _) = try await URLSession.shared.data(for: req)
        let data = try JSON.parse(raw)
        return (data["results"]?.array ?? []).map {
            SearchResult(url: $0["url"]?.string ?? "", title: $0["title"]?.string ?? "",
                         snippet: $0["highlights"]?.array?.first?.string ?? "")
        }
    }
}
