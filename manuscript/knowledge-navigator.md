# Knowledge Base Navigator: Building an AI-Powered Information System

In two of my other books I covered the classic Knowledge Graph Navigator (KGN) project that combined symbolic Natural Language Processing (NLP) with access to public knowledge graphs like Wikidata and DBPedia. In this chapter I take a simpler, more modern approach: a Swift command-line tool powered by Google's Gemini API.

The source code can be found in the directory: **source-code/knowledge-navigator/**.

In this chapter we explore a practical Swift application that combines modern AI APIs to create an interactive knowledge exploration tool. The Knowledge Base Navigator demonstrates how to integrate the Gemini REST API, decode JSON responses with `Codable`, and build an async interactive CLI loop — all in pure Swift with no third-party dependencies.

## Project Overview

The Knowledge Base Navigator is a modern evolution of the classic Knowledge Graph Navigator (KGN). This version uses Google's Gemini Flash LLM API to extract entities from natural language, disambiguate them, discover semantic links between entities, and retrieve detailed encyclopedic information. This represents a paradigm shift from traditional database-backed systems to an AI-driven pipeline.

The system follows a two-stage process:

1. **Entity Extraction**: The user provides text; Gemini identifies potential entities (people, companies, countries, etc.) and returns them as a numbered list
2. **Deep Retrieval**: The user selects entities by number; Gemini provides detailed facts and analyzes relationships between selected entities

## Project Structure

The Knowledge Navigator is a Swift Package Manager project:

```
knowledge-navigator/
├── Package.swift
└── Sources/KnowledgeNavigator/
    ├── main.swift        # Interactive CLI loop
    ├── GeminiAPI.swift   # URLSession-based Gemini client
    └── Models.swift      # Codable request/response structs
```

### Package Definition

`Package.swift` targets macOS 13+ to access Swift Concurrency (`async`/`await`) from a command-line entry point:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KnowledgeNavigator",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "KnowledgeNavigator",
            path: "Sources/KnowledgeNavigator"
        )
    ]
)
```

No external dependencies — the entire project relies on Swift's standard library and Foundation.

## Core Implementation

### Codable Models (`Models.swift`)

Swift's `Codable` protocol lets us define the Gemini request and response shapes as plain structs. The encoder and decoder handle all JSON serialization automatically:

```swift
// MARK: - Request

struct GeminiRequest: Codable {
    let contents: [Content]

    struct Content: Codable {
        let parts: [Part]
    }

    struct Part: Codable {
        let text: String
    }
}

// MARK: - Response

struct GeminiResponse: Codable {
    let candidates: [Candidate]?

    struct Candidate: Codable {
        let content: Content
    }

    struct Content: Codable {
        let parts: [Part]
    }

    struct Part: Codable {
        let text: String
    }
}
```

**Why nested structs?** The Gemini API wraps text in a hierarchy: `candidates → content → parts → text`. Modeling each level as a separate `Codable` struct makes decoding straightforward — no manual key traversal required.

**Why `candidates` is optional**: The API may return no candidates on error. Marking it `[Candidate]?` means decoding never throws on a malformed/empty response; we handle the missing value explicitly.

### Gemini API Client (`GeminiAPI.swift`)

The async function `getGeminiCompletion` wraps a `URLSession` data task and returns the model's text, or `nil` on any failure:

```swift
func getGeminiCompletion(userPrompt: String) async -> String? {
    guard
        let apiKey = ProcessInfo.processInfo
            .environment["GOOGLE_API_KEY"],
        !apiKey.isEmpty
    else {
        fputs("[Error] GOOGLE_API_KEY is not set.\n", stderr)
        return nil
    }

    let modelName = "models/gemini-2.5-flash"
    let base =
        "https://generativelanguage.googleapis.com/v1beta/"
    let urlString =
        "\(base)\(modelName):generateContent?key=\(apiKey)"

    guard let url = URL(string: urlString) else { return nil }

    let requestBody = GeminiRequest(
        contents: [
            GeminiRequest.Content(parts: [
                GeminiRequest.Part(text: userPrompt)
            ])
        ]
    )

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(
        "application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONEncoder().encode(requestBody)

    do {
        let (data, response) =
            try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            let body =
                String(data: data, encoding: .utf8) ?? "<no body>"
            fputs(
                "[Error] HTTP \(httpResponse.statusCode):" +
                " \(body)\n", stderr)
            return nil
        }

        let geminiResponse = try JSONDecoder().decode(
            GeminiResponse.self, from: data)
        return geminiResponse.candidates?
            .first?.content.parts.first?.text

    } catch {
        fputs(
            "[Error] Network or decoding error: \(error)\n",
            stderr)
        return nil
    }
}
```

**Key patterns**:

- `ProcessInfo.processInfo.environment["GOOGLE_API_KEY"]` reads the API key from the environment — the same pattern used throughout this book
- `JSONEncoder().encode(requestBody)` serializes the `GeminiRequest` struct directly; no manual JSON construction needed
- `try await URLSession.shared.data(for:)` is the modern async replacement for completion-handler networking
- `JSONDecoder().decode(GeminiResponse.self, from: data)` maps the response JSON onto our `Codable` structs
- Optional chaining (`?.first?.content.parts.first?.text`) navigates the nested response safely

**Response parsing**: The Gemini API returns a deeply nested structure. With `Codable` structs and optional chaining, we navigate it in a single expression rather than multiple guard/let bindings:

```swift
geminiResponse.candidates?.first?.content.parts.first?.text
```

### Parsing User Selection (`main.swift`)

Before the main loop, a small helper function tokenizes the user's comma/space-separated entity selections into integers:

```swift
func parseSelectionIndices(from line: String) -> [Int] {
    let separators = CharacterSet(charactersIn: " \t,")
    return line
        .components(separatedBy: separators)
        .filter { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
        .compactMap { Int($0) }
}
```

- `components(separatedBy:)` splits on spaces, tabs, and commas
- `allSatisfy(\.isNumber)` keeps only purely numeric tokens (rejects "1a", empty strings, etc.)
- `compactMap { Int($0) }` converts to integers, dropping any that fail

### Interactive CLI Loop (`main.swift`)

Swift 5.9 command-line tools support top-level `await` by wrapping async work in a `Task`:

```swift
let task = Task {
    print("╔══════════════════════════════════════════════╗")
    print("║  GEMINI KNOWLEDGE BASE NAVIGATOR (Swift)     ║")
    print("╚══════════════════════════════════════════════╝")

    while true {
        print("\nEnter entity names or a sentence ('quit' to exit):")
        print("> ", terminator: "")

        guard let userInput = readLine(),
              !userInput.isEmpty else { continue }

        if userInput.lowercased() == "quit"
            || userInput.lowercased() == "q" {
            print("Goodbye!")
            break
        }

        // Stage 1: entity extraction
        print("\n[Extracting entities using Gemini...]")
        let extractPrompt = """
        Analyze the following user text: "\(userInput)".
        Identify potential encyclopedic entities ...
        Return ONLY a numbered list with a short 1-sentence description.
        """

        guard let entityListText = await getGeminiCompletion(
            userPrompt: extractPrompt) else {
            print("[Error getting entity list. Try again.]")
            continue
        }

        print("\n--- IDENTIFIED ENTITIES ---")
        print(entityListText)
        print("---------------------------")

        // Stage 2: detail retrieval
        print("\nEnter entity numbers (space separated):")
        print("> ", terminator: "")

        guard let selectionLine = readLine(),
              !selectionLine.isEmpty else { continue }
        let indices = parseSelectionIndices(from: selectionLine)
        guard !indices.isEmpty else {
            print("[No valid selections. Returning to main prompt.]")
            continue
        }

        print("\n[Fetching detailed facts and relationships...]")
        let indicesString =
            indices.map(String.init).joined(separator: ", ")
        let detailPrompt = """
        Review this numbered list of entities:
        \(entityListText)

        The user selected entities: \(indicesString).
        For each: provide detailed encyclopedic information.
        Then summarize relationships among all selected entities.
        Use clean section headers and bullet points.
        """

        if let detailsText = await getGeminiCompletion(
            userPrompt: detailPrompt) {
            print("\n\(detailsText)")
        }
    }
}

_ = await task.value
```

**Key patterns**:

- `while true` with `break` on quit — the simplest correct pattern for a persistent CLI loop
- `readLine()` returns `String?`; `guard let` handles both EOF and empty input
- `print("> ", terminator: "")` suppresses the trailing newline so the cursor stays on the prompt line
- `await getGeminiCompletion(...)` suspends the loop (without blocking a thread) while the network call completes
- `_ = await task.value` at the end of the file ensures the process stays alive until the Task finishes

**Why wrap in `Task`?** Swift's top-level concurrency support requires either marking the entry point `@main` with an `async static func main()`, or wrapping async work in a `Task`. The `Task` approach is simpler for small command-line tools where you do not need dependency injection or structured concurrency hierarchies.

## Running the Application

```bash
# Set API key in your shell
export GOOGLE_API_KEY="your_api_key_here"

# From the project directory
cd source-code/knowledge-navigator
swift run KnowledgeNavigator
```

To run::

```bash
$ swift run KnowledgeNavigator
Building for debugging...
[7/7] Applying KnowledgeNavigator
Build of product 'KnowledgeNavigator' complete! (0.35s)
╔══════════════════════════════════════════════════════════╗
║        GEMINI KNOWLEDGE BASE NAVIGATOR (Swift)           ║
╚══════════════════════════════════════════════════════════╝

Enter entity names or a descriptive sentence (or 'quit' to exit):
> Bill Gates, Microsoft, Steve Jobs, Apple Computer

[Extracting entities using Gemini...]

--- IDENTIFIED ENTITIES ---
1.  **Bill Gates**: An American business magnate, software developer, investor, author, and philanthropist, best known as the co-founder of Microsoft Corporation.
2.  **Microsoft**: An American multinational technology corporation that produces computer software, consumer electronics, personal computers, and related services.
3.  **Steve Jobs**: An American business magnate, inventor, and investor who was the co-founder, chairman, and CEO of Apple Inc.
4.  **Apple Computer**: The former name of Apple Inc., an American multinational technology company that designs, manufactures, and markets consumer electronics, computer software, and online services.
---------------------------

Enter the numbers of the entities you want details for (space separated):
> 1 2 3 4

[Fetching detailed facts and relationships for selected entities...]

Here is a detailed review of the selected entities, followed by an evaluation of their collective relationships.

***

 ### Detailed Factual Information for Each Selected Entity

 #### 1. Bill Gates
*   **Full Name:** William Henry Gates III
*   **Born:** October 28, 1955 (age 68 as of 2023), Seattle, Washington, U.S.
*   **Nationality:** American
*   **Known For:** Co-founder of Microsoft Corporation, business magnate, software developer, investor, author, and philanthropist.
*   **Key Roles & Achievements:**
    *   Co-founded Microsoft with Paul Allen in 1975.
    *   Served as CEO of Microsoft until 2000, and as chairman and chief software architect until 2008. Remained chairman until 2014, and then technology advisor.
    *   Helped lead the personal computer revolution through Microsoft's operating systems (MS-DOS, Windows) and software applications (Microsoft Office).
    *   Co-founded the Bill & Melinda Gates Foundation in 2000, which is recognized as one of the world's largest private charitable foundations, focusing on global health, poverty, and education.
    *   Consistently ranked among the wealthiest people in the world.
*   **Education:** Attended Harvard University but dropped out to dedicate himself to Microsoft.
*   **Philanthropy:** Through the Bill & Melinda Gates Foundation, he has committed billions to various causes, including eradicating diseases like polio and malaria, improving sanitation, and advancing agricultural development.

 #### 2. Microsoft
*   **Full Name:** Microsoft Corporation
*   **Founded:** April 4, 1975
*   **Founders:** Bill Gates, Paul Allen
*   **Headquarters:** Redmond, Washington, U.S.
*   **Industry:** Technology (Software development, consumer electronics, personal computers, cloud computing, gaming, artificial intelligence, online services).
*   **Description:** An American multinational technology corporation that develops, manufactures, licenses, supports, and sells computer software, consumer electronics, personal computers, and related services. It is one of the world's largest software companies by revenue and one of the most valuable public companies globally.
*   **Key Products & Services:**
    *   **Operating Systems:** Microsoft Windows
    *   **Productivity Software:** Microsoft Office suite (Word, Excel, PowerPoint, Outlook, Teams)
    *   **Cloud Computing:** Microsoft Azure
    *   **Gaming:** Xbox series of video game consoles and services
    *   **Hardware:** Surface personal computers, HoloLens mixed reality headsets
    *   **Other:** LinkedIn (professional networking service), GitHub (software development platform), Bing (search engine), Edge (web browser).
*   **Leadership:** Satya Nadella (CEO), Brad Smith (President & Vice Chair).
*   **Financials (as of recent reporting):** Consistently reports hundreds of billions in annual revenue and tens of billions in net income, with a market capitalization often among the top few globally.

 #### 3. Steve Jobs
*   **Full Name:** Steven Paul Jobs
*   **Born:** February 24, 1955, San Francisco, California, U.S.
*   **Died:** October 5, 2011 (age 56), Palo Alto, California, U.S.
*   **Nationality:** American
*   **Known For:** Co-founder, chairman, and CEO of Apple Inc.; business magnate, inventor, and investor. He was a pioneer of the personal computer revolution of the 1970s and 1980s.
*   **Key Roles & Achievements:**
    *   Co-founded Apple Computer with Steve Wozniak and Ronald Wayne in 1976.
    *   Led Apple during the introduction of revolutionary products like the Macintosh computer, iPod, iPhone, and iPad, as well as the iTunes Store and App Store.
    *   Was ousted from Apple in 1985, after which he founded NeXT Inc., a computer platform development company specializing in higher education and business markets.
    *   Acquired The Graphics Group (later renamed Pixar Animation Studios) from Lucasfilm in 1986, which he built into a major animation studio before selling it to Disney.
    *   Returned to Apple in 1997 as an interim CEO and then full-time CEO, revitalizing the company and leading it to unprecedented success.
    *   Recognized for his vision in combining aesthetics, user-friendliness, and advanced technology.
*   **Education:** Attended Reed College but dropped out after one semester.
*   **Legacy:** Remembered as a charismatic and visionary leader whose work profoundly impacted the technology, music, and animation industries.

 #### 4. Apple Computer (Apple Inc.)
*   **Former Name:** Apple Computer, Inc. (used until January 9, 2007)
*   **Current Name:** Apple Inc.
*   **Founded:** April 1, 1976
*   **Founders:** Steve Jobs, Steve Wozniak, Ronald Wayne
*   **Headquarters:** Cupertino, California, U.S.
*   **Industry:** Technology (Consumer electronics, computer software, online services, digital content distribution, artificial intelligence, automotive).
*   **Description:** An American multinational technology company that designs, manufactures, and markets consumer electronics, computer software, and online services. It is one of the "Big Five" American information technology companies and is consistently ranked among the world's largest companies by revenue and market capitalization.
*   **Key Products & Services:**
    *   **Smartphones:** iPhone
    *   **Personal Computers:** Mac (MacBook, iMac, Mac Pro, Mac Studio)
    *   **Tablets:** iPad
    *   **Wearables & Accessories:** Apple Watch, AirPods, HomePod
    *   **Operating Systems:** iOS, iPadOS, macOS, watchOS, tvOS
    *   **Software & Services:** App Store, iTunes Store, Apple Music, Apple TV+, Apple Pay, iCloud, Safari.
*   **Leadership:** Tim Cook (CEO).
*   **Financials (as of recent reporting):** Apple is the world's largest technology company by revenue, with annual revenues often exceeding hundreds of billions of dollars and a market capitalization that frequently makes it the world's most valuable public company.

***

 ### Collective Relationships, Associations, and Historical Connections

The selected entities – Bill Gates, Microsoft, Steve Jobs, and Apple Computer (Apple Inc.) – are deeply intertwined through a complex history of innovation, intense competition, collaboration, and personal rivalry that shaped the modern technology landscape.

*   **Founders and Their Creations:**
    *   **Bill Gates** is the visionary co-founder and long-time leader of **Microsoft**. He drove the company's dominance in the software market, particularly with the Windows operating system and Microsoft Office suite.
    *   **Steve Jobs** is the iconic co-founder and transformative CEO of **Apple Computer (Apple Inc.)**. He spearheaded Apple's development of integrated hardware and software products, defining user experience with the Macintosh, iPod, iPhone, and iPad.

*   **Direct Competition and Rivalry:**
    *   **Microsoft and Apple** were, and to some extent still are, fierce competitors, particularly in the personal computer market. Their rivalry dates back to the early days of personal computing, intensifying with the advent of graphical user interfaces (GUIs).
    *   Apple, under Steve Jobs, pioneered the commercial GUI with the Macintosh in 1984. Microsoft, under Bill Gates, subsequently launched Windows, which brought a GUI to IBM-compatible PCs and eventually dominated the market due to its widespread adoption across many hardware manufacturers. This led to a long-standing "look and feel" lawsuit initiated by Apple against Microsoft.
    *   The competition extended to operating systems (macOS vs. Windows), office productivity software (Microsoft Office vs. Apple's iWork), and eventually into other areas like digital media and mobile devices.

*   **Interdependence and Collaboration:**
    *   Despite their rivalry, **Microsoft** was a critical software developer for **Apple's** Macintosh platform in its early days, creating essential applications like Microsoft Word and Excel that were crucial for the Mac's commercial viability.
    *   In 1997, when Apple was nearing bankruptcy during Steve Jobs's return, **Microsoft** made a significant \$150 million investment in non-voting Apple stock. This partnership also included a commitment from Microsoft to continue developing Office for Mac and for Apple to make Internet Explorer the default browser on Mac (temporarily). This move, announced by Bill Gates himself at Macworld, was instrumental in keeping Apple afloat and allowed Jobs to implement his turnaround strategy.

*   **Personal Rivalry and Mutual Respect:**
    *   **Bill Gates and Steve Jobs** were the two most prominent figures of their generation in the tech world. Their relationship was characterized by intense professional rivalry, contrasting business philosophies (Microsoft's software licensing vs. Apple's integrated ecosystem), and a complicated personal dynamic involving both admiration and occasional animosity.
    *   Both men pushed the boundaries of technology and user experience, with their respective companies often leapfrogging each other in innovation. They often drew inspiration from and reacted to each other's product announcements and strategies.
    *   Towards the end of Jobs's life, their relationship reportedly softened, with a mutual respect for each other's contributions to the industry becoming more apparent.

In essence, these four entities represent the two dominant poles of the personal computing revolution and beyond. Bill Gates and Microsoft championed an open software ecosystem, while Steve Jobs and Apple pioneered a tightly integrated hardware and software experience. Their intertwined history of innovation, competition, and strategic alliances profoundly shaped the technological landscape we know today.

Enter entity names or a descriptive sentence (or 'quit' to exit):
> 
```

### Example Session

```
╔══════════════════════════════════════════════════════════╗
║        GEMINI KNOWLEDGE BASE NAVIGATOR (Swift)           ║
╚══════════════════════════════════════════════════════════╝

Enter entity names or a descriptive sentence (or 'quit' to exit):
> Bill Gates and Microsoft

[Extracting entities using Gemini...]

--- IDENTIFIED ENTITIES ---
1. Bill Gates: An American business magnate, software developer, and philanthropist who co-founded Microsoft Corporation.
2. Microsoft: A multinational technology corporation that develops, manufactures, and licenses computer software.
---------------------------

Enter entity numbers (space separated):
> 1 2

[Fetching detailed facts and relationships...]

=== BILL GATES ===
* Born: October 28, 1955, Seattle, Washington
* Occupation: Business magnate, investor, philanthropist
* Net Worth: ~$120 billion (as of 2024)
* Founded Microsoft in 1975 with Paul Allen

=== MICROSOFT ===
* Founded: April 4, 1975
* Headquarters: Redmond, Washington
* Industry: Technology, Software, Cloud Computing
* Revenue: $211 billion (2023)

=== RELATIONSHIP ===
Bill Gates co-founded Microsoft with Paul Allen in 1975. He served as CEO until 2000
and remained Chairman until 2014. Microsoft was the primary source of Gates' wealth.
```

## Key Takeaways

1. **`Codable` for REST APIs**: Define the request and response shapes as nested `Codable` structs — no third-party JSON library needed
2. **Async URLSession**: `try await URLSession.shared.data(for:)` replaces callback-based networking with clean, linear code
3. **Two-Stage LLM Pipelines**: Chaining two Gemini calls (extract entities → fetch details) keeps each prompt focused and yields higher-quality output
4. **Prompt Engineering**: Tell the model exactly what format to return — "ONLY the numbered list" prevents verbose conversational padding
5. **Top-Level Async**: Wrap async CLI work in a `Task` and `await task.value` at the end of `main.swift` to keep the process alive
6. **Zero External Dependencies**: Foundation's `URLSession`, `JSONEncoder`, and `JSONDecoder` are sufficient for a production-quality Gemini client

## Environment Setup

```bash
# macOS 13+ and Xcode 15+ required
xcode-select --install   # if needed

# API key
export GOOGLE_API_KEY="your_api_key_here"

# Build and run
cd source-code/knowledge-navigator
swift run KnowledgeNavigator
```

---

This project shows that building an AI-powered interactive tool in Swift requires very little boilerplate. `Codable`, `URLSession`, and Swift Concurrency together replace what traditionally needed multiple libraries — making the resulting code both concise and easy to maintain.
