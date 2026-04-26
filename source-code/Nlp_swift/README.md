# Natural Language Processing — Example for Mark Watson's book "Artificial Intelligence Using Swift"

Book URI: https://leanpub.com/SwiftAI

You can read my book for free online at: https://leanpub.com/SwiftAI/read

Demonstrates Apple's NaturalLanguage framework for on-device NLP tasks:

- **Named Entity Recognition** — identifying people, places, and organizations
- **Lemmatization** — reducing words to their base forms
- **Language Detection** — identifying the language of text
- **Sentiment Analysis** — scoring text as positive, negative, or neutral
- **Word Embeddings** — finding semantically similar words

## Run

    swift build
    swift run

## Key Source Files

| File | Description |
|---|---|
| `Sources/Nlp_swift/NLP.swift` | NLP utility functions using NLTagger, NLLanguageRecognizer, and NLEmbedding |
| `Sources/Nlp_swift/main.swift` | Interactive demo exercising all NLP capabilities |

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
