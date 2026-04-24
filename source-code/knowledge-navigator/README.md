# Knowledge Base Navigator (Swift / Gemini Edition)

An AI-powered command-line tool that extracts encyclopedic entities from
natural language and retrieves detailed information via Google's Gemini API.

## Requirements

- macOS 13+
- Xcode 15+ / Swift 5.9+
- A Google Gemini API key

## Setup

```bash
export GOOGLE_API_KEY="your_api_key_here"
```

## Run

```bash
cd source-code/knowledge-navigator
swift run KnowledgeNavigator
```

## Project Layout

```
knowledge-navigator/
├── Package.swift
└── Sources/KnowledgeNavigator/
    ├── main.swift        # Interactive CLI loop
    ├── GeminiAPI.swift   # URLSession-based Gemini client
    └── Models.swift      # Codable request/response structs
```
