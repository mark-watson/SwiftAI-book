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

/// Helper to parse HTML data into a SwiftSoup Document.
private func parse(data: Data, uri: String) throws -> Document {
    guard let html = String(data: data, encoding: .utf8) else {
        throw ScrapingError.parseFailed(
            NSError(
                domain: "WebScraping",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Failed to decode UTF-8 data"
                ]
            )
        )
    }

    do {
        return try SwiftSoup.parse(html, uri)
    } catch {
        throw ScrapingError.parseFailed(error)
    }
}

/// Fetches the HTML document from a given URI and parses it asynchronously.
private func fetchDocument(uri: String) async throws -> Document {
    guard let url = URL(string: uri) else {
        throw ScrapingError.invalidURL(uri)
    }

    let data: Data
    do {
        (data, _) = try await URLSession.shared.data(from: url)
    } catch {
        throw ScrapingError.fetchFailed(error)
    }

    return try parse(data: data, uri: uri)
}

/// Fetches the HTML document from a given URI and parses it synchronously.
private func fetchDocument(uri: String) throws -> Document {
    guard let url = URL(string: uri) else {
        throw ScrapingError.invalidURL(uri)
    }

    let data: Data
    do {
        data = try Data(contentsOf: url)
    } catch {
        throw ScrapingError.fetchFailed(error)
    }

    return try parse(data: data, uri: uri)
}

/// Returns the plain text content of a web page (asynchronous).
public func webPageText(uri: String) async throws -> String {
    let doc = try await fetchDocument(uri: uri)
    return try doc.text()
}

/// Returns the plain text content of a web page (synchronous).
public func webPageText(uri: String) throws -> String {
    let doc = try fetchDocument(uri: uri)
    return try doc.text()
}

/// Helper for headers (asynchronous).
private func webPageHeadersHelper(
    uri: String,
    headerName: String
) async throws -> [String] {
    let doc = try await fetchDocument(uri: uri)
    let headers = try doc.select(headerName)
    return try headers.map { try $0.text() }
}

/// Helper for headers (synchronous).
private func webPageHeadersHelper(
    uri: String,
    headerName: String
) throws -> [String] {
    let doc = try fetchDocument(uri: uri)
    let headers = try doc.select(headerName)
    return try headers.map { try $0.text() }
}

/// Returns all H1 headers on the page (asynchronous).
public func webPageH1Headers(uri: String) async throws -> [String] {
    return try await webPageHeadersHelper(uri: uri, headerName: "h1")
}

/// Returns all H1 headers on the page (synchronous).
public func webPageH1Headers(uri: String) throws -> [String] {
    return try webPageHeadersHelper(uri: uri, headerName: "h1")
}

/// Returns all H2 headers on the page (asynchronous).
public func webPageH2Headers(uri: String) async throws -> [String] {
    return try await webPageHeadersHelper(uri: uri, headerName: "h2")
}

/// Returns all H2 headers on the page (synchronous).
public func webPageH2Headers(uri: String) throws -> [String] {
    return try webPageHeadersHelper(uri: uri, headerName: "h2")
}

/// Returns all anchors (links) found on the page as `Anchor` objects (asynchronous).
public func webPageAnchors(uri: String) async throws -> [Anchor] {
    let doc = try await fetchDocument(uri: uri)
    return try parseAnchors(doc: doc, uri: uri)
}

/// Returns all anchors (links) found on the page as `Anchor` objects (synchronous).
public func webPageAnchors(uri: String) throws -> [Anchor] {
    let doc = try fetchDocument(uri: uri)
    return try parseAnchors(doc: doc, uri: uri)
}

/// Shared anchor parsing logic.
private func parseAnchors(doc: Document, uri: String) throws -> [Anchor] {
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
