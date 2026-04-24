import XCTest
import Foundation
@testable import WebScraping_swift

final class WebScrapingTests: XCTestCase {
    let testURL = "https://markwatson.com"

    func testWebPageText() async throws {
        let text = try await webPageText(uri: testURL)
        XCTAssertFalse(text.isEmpty, "Text from Mark's site should not be empty.")
    }

    func testWebPageH1Headers() async throws {
        let h1Headers = try await webPageH1Headers(uri: testURL)
        XCTAssertFalse(h1Headers.isEmpty, "H1 headers should not be empty.")
        print("++ h1_headers:", h1Headers)
    }

    func testWebPageH2Headers() async throws {
        let h2Headers = try await webPageH2Headers(uri: testURL)
        XCTAssertFalse(h2Headers.isEmpty, "H2 headers should not be empty.")
        print("++ h2_headers:", h2Headers)
    }

    func testWebPageAnchors() async throws {
        let anchors = try await webPageAnchors(uri: testURL)
        XCTAssertFalse(anchors.isEmpty, "Anchors should not be empty.")
        
        // Ensure URLs are fully qualified
        for anchor in anchors {
            XCTAssertNotNil(anchor.url.scheme, "Anchor URL should have a scheme: \(anchor.url)")
            XCTAssertNotNil(anchor.url.host, "Anchor URL should have a host: \(anchor.url)")
        }
    }
}
