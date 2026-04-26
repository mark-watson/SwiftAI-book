# Part 1: Getting Started with Swift for AI Development

Welcome to Part 1, where we lay the groundwork for everything that follows.

If you are an experienced Swift developer you may be tempted to skip this section, but I encourage you to at least skim it — the chapters here introduce patterns and utility libraries that reappear throughout the book.

We begin with a practical guide to **setting up Swift for command-line development**. Most of the projects in this book are terminal-based tools rather than graphical applications, so this chapter walks you through the Swift Package Manager, shows how to create executable and library packages, and explains the mono-repo umbrella `Package.swift` that ties all the book's examples together. You will also see how to reference one book example as a dependency of another — a pattern we use repeatedly in later chapters.

Next, we build a pair of small but genuinely useful libraries. The **command-line utilities** chapter develops `ShellProcess_swift`, a thin wrapper around Foundation's `Process` API that lets you launch shell commands and capture their output from Swift. We combine it with file I/O examples so you have a complete toolkit for writing the kind of data-processing scripts that AI work constantly demands. We also introduce the Swift REPL and show how to import your own packages into it for interactive experimentation.

Part 1 closes with a **web scraping** chapter. Working with AI almost always means working with data, and the web is the largest data source there is. We build `WebScraping_swift`, a library based on SwiftSoup (the Swift port of BeautifulSoup) that extracts plain text, headings, and hyperlinks from any web page. The library provides both synchronous and asynchronous (`async/await`) APIs with proper error handling via a typed `ScrapingError` enum — a small preview of the modern Swift concurrency style we use throughout the rest of the book.

By the end of Part 1 you will be comfortable creating Swift packages, running shell processes, reading and writing files, scraping web content, and working at the command line. These foundational skills make the AI chapters that follow much easier to approach.
