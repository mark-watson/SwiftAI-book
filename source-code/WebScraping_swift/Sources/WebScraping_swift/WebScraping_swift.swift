import Foundation
import SwiftSoup

public enum ScrapingError: Error {
    case invalidURL(String)
    case fetchFailed(Error)
    case parseFailed(Error)
}

public struct Anchor: Equatable {
    public let text: String
    public let url: URL
}

/// Fetches the HTML document from a given URI and parses it.
private func fetchDocument(uri: String) async throws -> Document {
    guard let url = URL(string: uri) else {
        throw ScrapingError.invalidURL(uri)
    }
    
    let (data, _) = try await URLSession.shared.data(from: url)
    
    guard let html = String(data: data, encoding: .utf8) else {
        // Fallback or retry with different encoding if needed, but UTF-8 is standard.
        throw ScrapingError.parseFailed(NSError(domain: "WebScraping", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to decode UTF-8 data"]))
    }
    
    do {
        return try SwiftSoup.parse(html, uri)
    } catch {
        throw ScrapingError.parseFailed(error)
    }
}

/// Returns the plain text content of a web page.
public func webPageText(uri: String) async throws -> String {
    let doc = try await fetchDocument(uri: uri)
    return try doc.text()
}

/// Returns all headers of a specific type (e.g., "h1", "h2").
private func webPageHeadersHelper(uri: String, headerName: String) async throws -> [String] {
    let doc = try await fetchDocument(uri: uri)
    let headers = try doc.select(headerName)
    return try headers.map { try $0.text() }
}

/// Returns all H1 headers on the page.
public func webPageH1Headers(uri: String) async throws -> [String] {
    return try await webPageHeadersHelper(uri: uri, headerName: "h1")
}

/// Returns all H2 headers on the page.
public func webPageH2Headers(uri: String) async throws -> [String] {
    return try await webPageHeadersHelper(uri: uri, headerName: "h2")
}

/// Returns all anchors (links) found on the page as `Anchor` objects.
public func webPageAnchors(uri: String) async throws -> [Anchor] {
    let doc = try await fetchDocument(uri: uri)
    let anchors = try doc.select("a")
    let baseURL = URL(string: uri)
    
    return try anchors.compactMap { a -> Anchor? in
        let text = try a.text()
        let href = try a.attr("href")
        
        // Use Foundation's URL resolution for relative/fragment links.
        guard let resolvedURL = URL(string: href, relativeTo: baseURL) else {
            return nil
        }
        
        return Anchor(text: text, url: resolvedURL.absoluteURL)
    }
}
