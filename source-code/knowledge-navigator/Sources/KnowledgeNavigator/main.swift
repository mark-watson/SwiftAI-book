// main.swift
// Knowledge Base Navigator — interactive CLI powered by Google Gemini.
//
// Usage:
//   export GOOGLE_API_KEY="your_key_here"
//   swift run KnowledgeNavigator

import Foundation

// MARK: - Helpers

/// Parse space/comma-separated tokens from a string, returning only those
/// that represent positive integers (for entity-number selection).
func parseSelectionIndices(from line: String) -> [Int] {
    let separators = CharacterSet(charactersIn: " \t,")
    return line
        .components(separatedBy: separators)
        .filter { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
        .compactMap { Int($0) }
}

// MARK: - Main async entry point

// Swift 5.9 command-line tools can wrap async work in a top-level Task.
let task = Task {
    print("╔══════════════════════════════════════════════════════════╗")
    print("║        GEMINI KNOWLEDGE BASE NAVIGATOR (Swift)           ║")
    print("╚══════════════════════════════════════════════════════════╝")

    while true {
        print("\nEnter entity names or a descriptive sentence (or 'quit' to exit):")
        print("> ", terminator: "")

        guard let userInput = readLine(), !userInput.isEmpty else { continue }

        if userInput.lowercased() == "quit" || userInput.lowercased() == "q" {
            print("Goodbye!")
            break
        }

        // ── Stage 1: Entity extraction ───────────────────────────────
        print("\n[Extracting entities using Gemini...]")

        let extractPrompt = """
        Analyze the following user text: "\(userInput)".
        Identify potential encyclopedic entities (people, companies, countries, cities, products, concepts, etc.) mentioned.
        Categorize them if necessary. Return them as a neatly formatted numbered list (1., 2., 3., etc.) with a short 1-sentence description for each.
        DO NOT return any other conversational text, ONLY the numbered list so the user can see their options.
        """

        guard let entityListText = await getGeminiCompletion(userPrompt: extractPrompt) else {
            print("[Error getting entity list from Gemini. Please try again.]")
            continue
        }

        print("\n--- IDENTIFIED ENTITIES ---")
        print(entityListText)
        print("---------------------------")

        // ── Stage 2: Detail retrieval ────────────────────────────────
        print("\nEnter the numbers of the entities you want details for (space separated):")
        print("> ", terminator: "")

        guard let selectionLine = readLine(), !selectionLine.isEmpty else {
            print("[No input. Returning to main prompt.]")
            continue
        }

        let indices = parseSelectionIndices(from: selectionLine)
        guard !indices.isEmpty else {
            print("[No valid selections made. Returning to main prompt.]")
            continue
        }

        print("\n[Fetching detailed facts and relationships for selected entities...]")

        let indicesString = indices.map(String.init).joined(separator: ", ")
        let detailPrompt = """
        Review this numbered list of entities:
        \(entityListText)

        The user has specifically selected the following entity numbers from the list: \(indicesString).
        Task 1: For each selected entity, generate detailed, factual, encyclopedic information (e.g. birth place, description, and relationships for people; industry, net income, and description for companies; similar details for countries, cities, or products).
        Task 2: Evaluate ALL the selected entities collectively and explicitly summarize any known relationships, associations, or historical connections among them.
        Format the output with clean section headers and bullet points.
        """

        if let detailsText = await getGeminiCompletion(userPrompt: detailPrompt) {
            print("\n\(detailsText)")
        } else {
            print("[Error fetching details. Please try again.]")
        }
    }
}

// Run the async task and wait for it to complete before the process exits.
_ = await task.value
