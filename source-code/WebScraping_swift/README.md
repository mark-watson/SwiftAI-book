# WebScraping — Example for Mark Watson's book "Artificial Intelligence Using Swift"

Book URI: https://leanpub.com/SwiftAI

You can read my book for free online at: https://leanpub.com/SwiftAI/read

A Swift library for extracting content from web pages using [SwiftSoup](https://github.com/scinfu/SwiftSoup) (a port of Java's jsoup). Every function is available in both **async** and **synchronous** variants, making it easy to use in scripts, REPLs, and modern `async/await` code alike.

## API

| Function | Returns |
|---|---|
| `webPageText(uri:)` | Plain text content of the page |
| `webPageH1Headers(uri:)` | Array of all `<h1>` header texts |
| `webPageH2Headers(uri:)` | Array of all `<h2>` header texts |
| `webPageAnchors(uri:)` | Array of `Anchor(text:, url:)` structs for every link |

## Usage in Swift REPL

```bash
swift run --repl
```

```swift
import WebScraping_swift

// Synchronous (convenient for REPL)
let text = try webPageText(uri: "https://markwatson.com")
print(text)

// Async
let headers = try await webPageH1Headers(uri: "https://markwatson.com")
print(headers)
```

## Build & Test

    swift build
    swift test

> **Note:** The first build will show warnings from the SwiftSoup library — these are safe to ignore.

![HTML scraping library architecture](FIG_WebScraping_swift.jpg)

## Book Cover Material, Copyright, and License

This example is released using the Apache 2 license.

Copyright 2022-2026 Mark Watson. All rights reserved.

## This Book is Licensed with Creative Commons Attribution CC BY Version 3 That Allows Reuse In Derived Works

You are free to:

- Share — copy and redistribute the material in any medium or format
- Adapt — remix, transform, and build upon the material
for any purpose, even commercially.

You are required to give appropriate credit in any derived works:

```text
This work is derived from all or part of "Artificial Intelligence Using Swift" by
Mark Watson. Source: https://leanpub.com/SwiftAI
```

Please visit the [author's website](http://markwatson.com).
