# Web Scraping

It is important to respect the property rights of web site owners and abide by their terms and conditions for use. This [Wikipedia article on Fair Use](https://en.wikipedia.org/wiki/Fair_use) provides a good overview of using copyright material.

The web scraping code we develop here uses the Python BeautifulSoup and URI libraries.

For my work and research, I have been most interested in using web scraping to collect text data for natural language processing but other common applications include writing AI news collection and summarization assistants, trying to predict stock prices based on comments in social media which is what we did at Webmind Corporation in 2000 and 2001, etc.

{lang="swift",linenos=on}
~~~~~~~~
import Foundation
import SwiftSoup

public func webPageText(uri: String) -> String {
    guard let myURL = URL(string: uri) else {
        print("Error: \(uri) doesn't seem to be a valid URL")
        fatalError("invalid URI")
    }
    let html = try! String(contentsOf: myURL, encoding: .ascii)
    let doc: Document = try! SwiftSoup.parse(html)
    let plain_text = try! doc.text()
    return plain_text
}

func webPageHeadersHelper(uri: String, headerName: String) -> [String] {
    var ret: [String] = []
    guard let myURL = URL(string: uri) else {
        print("Error: \(uri) doesn't seem to be a valid URL")
        fatalError("invalid URI")
    }
    do {
        let html = try String(contentsOf: myURL, encoding: .ascii)
        let doc: Document = try SwiftSoup.parse(html)
        let h1_headers = try doc.select(headerName)
        for el in h1_headers {
            let h1 = try el.text()
            ret.append(h1)
        }
    } catch {
        print("Error")
    }
    return ret
}


public func webPageH1Headers(uri: String) -> [String] {
    return webPageHeadersHelper(uri: uri, headerName: "h1")
}
    
public func webPageH2Headers(uri: String) -> [String] {
    return webPageHeadersHelper(uri: uri, headerName: "h2")
}


public func webPageAnchors(uri: String) -> [[String]] {
    var ret: [[String]] = []
    guard let myURL = URL(string: uri) else {
        print("Error: \(uri) doesn't seem to be a valid URL")
        fatalError("invalid URI")
    }
    do {
        let html = try String(contentsOf: myURL, encoding: .ascii)
        let doc: Document = try SwiftSoup.parse(html)
        let anchors = try doc.select("a")
        for a in anchors {
            let text = try a.text()
            let a_uri = try a.attr("href")
            if a_uri.hasPrefix("#") {
                ret.append([text, uri + a_uri])
            } else {
                ret.append([text, a_uri])
            }
        }
    } catch {
        print("Error")
    }
    return ret
}
~~~~~~~~


{lang="swift",linenos=on}
~~~~~~~~
import XCTest
import Foundation
import SwiftSoup

@testable import WebScraping_swift

final class WebScrapingTests: XCTestCase {
    func testGetWebPage() {
        let text = webPageText(uri: "https://markwatson.com")
        print("\n\n\tTEXT FROM MARK's WEB SITE:\n\n", text)
    }

    func testToShowSwiftSoupExamples() {
        let myURLString = "https://markwatson.com"
        let h1_headers = webPageH1Headers(uri: myURLString)
        print("\n\n++ h1_headers:", h1_headers)
        let h2_headers = webPageH2Headers(uri: myURLString)
        print("\n\n++ h2_headers:", h2_headers)
        let anchors = webPageAnchors(uri: myURLString)
        print("\n\n++ anchors:", anchors)
}

    static var allTests = [("testGetWebPage", testGetWebPage),
                           ("testToShowSwiftSoupExamples", testToShowSwiftSoupExamples)]
}
~~~~~~~~

TBD:....

We will use [https://vapor.codes web services library](https://vapor.codes)
in this chapter to fetch data from web services and also in the next chapter for building a web application.

The tests with much output not shown for brevity:

{lang="bash",linenos=on}
~~~~~~~~
$ swift test

	TEXT FROM MARK's WEB SITE:

 Mark Watson: AI Practitioner and Polyglot Programmer | Mark Watson    Read my Blog    Fun stuff    My Books    My Open Source Projects    Hire Me    Free Mentoring    Privacy Policy Mark Watson: AI Practitioner and Polyglot Programmer I am the author of 20+ books on Artificial Intelligence, Common Lisp, Deep Learning, Haskell, Clojure, Java, Ruby, Hy language, and the Semantic Web. I have 55 US Patents. My customer list includes: Google, Capital One, Olive AI, CompassLabs, Disney, SAIC, Americast, PacBell, CastTV, Lutris Technology, Arctan Group, Sitescout.com, Embed.ly, and Webmind Corporation.

++ h1_headers: ["Mark Watson: AI Practitioner and Polyglot Programmer", "The books that I have written", "Fun stuff", "Open Source", "Hire Me", "Free Mentoring", "Privacy Policy"]

++ h2_headers: ["I am the author of 20+ books on Artificial Intelligence, Common Lisp, Deep Learning, Haskell, Clojure, Java, Ruby, Hy language, and the Semantic Web. I have 55 US Patents.", "Other published books:"]

++ anchors: [["Read my Blog", "https://mark-watson.blogspot.com"], ["Fun stuff", "https://markwatson.com#fun"], ["My Books", "https://markwatson.com#books"], ["My Open Source Projects", "https://markwatson.com#opensource"], ["Hire Me", "https://markwatson.com#consulting"], ["Free Mentoring", "https://markwatson.com#mentoring"], ["Privacy Policy", "https://markwatson.com/privacy.html"], ["leanpub", "https://leanpub.com/u/markwatson"], ["GitHub", "https://github.com/mark-watson"], ["LinkedIn", "https://www.linkedin.com/in/marklwatson/"], ["Twitter", "https://twitter.com/mark_l_watson"], ["leanpub", "https://leanpub.com/lovinglisp"], ["leanpub", "https://leanpub.com/haskell-cookbook/"], ["leanpub", "https://leanpub.com/javaai"], 
]
Test Suite 'All tests' passed at 2021-08-06 17:37:11.062.
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.471 (0.472) seconds
~~~~~~~~


