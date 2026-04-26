# Using the AnyLanguageModel Package - Examples for Mark Watson's book "Artificial Intelligence Using Swift"

Book URI: https://leanpub.com/SwiftAI

You can read my book for free online at: https://leanpub.com/SwiftAI/read

This project demonstrates how to use the [AnyLanguageModel](https://github.com/huggingface/AnyLanguageModel) package from Hugging Face to interact with multiple LLM providers through a single, unified API that mirrors Apple's FoundationModels framework.

## Prerequisites

- Swift 6.1+
- For the OpenAI example: set `OPENAI_API_KEY` environment variable
- For the Gemini example: set `GOOGLE_API_KEY` environment variable
- For the Ollama example: Ollama running locally with `qwen3:1.7b` pulled

## Examples

### OpenAI (gpt-4o-mini)

```bash
export OPENAI_API_KEY=your_key_here
swift run openai-example
```

### Google Gemini with Tool Calling (gemini-2.5-flash)

```bash
export GOOGLE_API_KEY=your_key_here
swift run gemini-example
```

### Ollama Local (qwen3:1.7b)

```bash
ollama pull qwen3:1.7b
swift run ollama-example
```

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

This eBook will be updated occasionally so please periodically check the [leanpub.com web page for this book](https://leanpub.com/SwiftAI) for updates.

Please visit the [author's website](http://markwatson.com).

If you found a copy of this book on the web and find it of value then please consider buying a copy at [leanpub.com/SwiftAI](https://leanpub.com/SwiftAI) to support the author and fund work for future updates. You can also see all of my books on [my website https://markwatson.com/](https://markwatson.com/).
