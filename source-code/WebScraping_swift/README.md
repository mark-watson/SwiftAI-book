# WebScraping

Example from my book "Artificial Intelligence Using Swift"

You can read my book for free online at: https://leanpub.com/SwiftAI/read

This is a very simple use of the SwiftSoup library that just returns the 
plain text from a web page. Extend this as-needed to process headers,
lists, etc. using the [documentation](https://github.com/scinfu/SwiftSoup).

## Usage in Swift REPL

You can use this library in the Swift REPL for quick experiments. To start the REPL with the library loaded, run:

```bash
swift run --repl
```

Once in the REPL, import the library:

```swift
import WebScraping_swift
```

### Synchronous Usage (Recommended for REPL)

For convenience, synchronous versions of the functions are available:

```swift
let text = try webPageText(uri: "https://markwatson.com")
print(text)
```

### Asynchronous Usage

If you prefer to use modern Swift concurrency, use `try await`:

```swift
let text = try await webPageText(uri: "https://markwatson.com")
print(text)
```

The second unit test function **testToShowSwiftSoupStructureExamples**
also shows examples of accessing the structure of a web page.

Note that the first time that you do a

    swift build
    swift test

you will see warning from the SwiftSoup library that you can ignore.

# This is an example program in my book "Artificial Intelligence Using Swift"

This example is released using the Apache 2 license.

## Book Cover Material, Copyright, and License

Copyright 2022-2026 Mark Watson. All rights reserved.

## This Book is Licensed with Creative Commons Attribution CC BY Version 3 That Allows Reuse In Derived Works

You are free to:

- Share — copy and redistribute the material in any medium or format
- Adapt — remix, transform, and build upon the material
for any purpose, even commercially.

You are required to give appropriate credit in any derived works:

```text
This work is derived from all or part of "Artificial Intelligence Using Swift" by
Mark Watson. Source: https://leanpub.com/lovinglisp
```

This eBook will be updated occasionally so please periodically check the [leanpub.com web page for this book](https://leanpub.com/SwiftAI) for updates.


Please visit the [author's website](http://markwatson.com).

If you found a copy of this book on the web and find it of value then please consider buying a copy at [leanpub.com/SwiftAI](https://leanpub.com/SwiftAI) to support the author and fund work for future updates.  You can also see all of my books on [my website https://markwatson.com/#books](https://markwatson.com/#books).
