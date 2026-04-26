# Part 5: Apple Intelligence and Applied AI Projects

This final part of the book brings together everything we have covered — LLMs, NLP, embeddings, retrieval, and structured data — in a collection of practical, self-contained projects. We begin with two chapters that showcase Apple's new on-device AI capabilities and then move into applied AI tools that solve real problems.

## Apple Intelligence: On-Device LLMs with FoundationModels

Apple's **FoundationModels** framework, introduced with macOS 26 (Tahoe), gives Swift developers direct access to the system's built-in language model — no API keys, no network requests, and no data leaving the device. We explore this framework in two chapters.

The first builds a **streaming chat tool** that verifies model availability, initializes a `LanguageModelSession` with a system prompt and temperature setting, and enters an interactive read-evaluate-print loop. Each response is streamed token-by-token to the terminal for a real-time typewriter effect. A `DispatchSource` signal handler lets you press Control-C to cancel a long response without killing the process — a small but important usability detail.

The second chapter takes this further with an **AI coding assistant**. The tool walks a project directory, reads every Swift, Python, and Lisp source file it finds, and asks the on-device model to summarize each file and the project as a whole. It then drops into a streaming chat loop so you can ask follow-up questions about the codebase. The summarization pass uses `temperature: 0` for deterministic, factual output, while the chat session uses a separate `LanguageModelSession` with `temperature: 0.2` for slightly more creative responses. Run it inside any repository and you get an instant, context-aware, fully private coding companion.

## Applied AI Projects

The remaining chapters demonstrate AI techniques beyond LLM chat:

**Anomaly Detection** implements a Gaussian anomaly detection model trained on the University of Wisconsin Breast Cancer dataset. The algorithm fits a per-feature Gaussian distribution to "normal" training examples, tunes an epsilon threshold against a cross-validation set, and evaluates precision, recall, and F1 on a held-out test set. The chapter demonstrates an important real-world scenario: when anomalies are rare and your training data is heavily unbalanced, anomaly detection outperforms standard supervised classification. The Swift implementation includes log-transform preprocessing to push features toward Gaussian distributions and ASCII histogram visualization for exploratory data analysis.

**AutoContext** tackles the problem of using small, local LLMs with limited context windows on large document collections. It implements a hybrid retrieval system that combines **BM25** (lexical/keyword search) with **vector similarity** (semantic search using Gemini embeddings) to identify the most relevant text chunks for any query. The results are merged, deduplicated, and formatted into a compact, targeted prompt ready for any LLM. This is the same Retrieval-Augmented Generation pattern we saw earlier in the book, but with a self-contained BM25 implementation and a focus on generating prompts rather than directly querying a model — making it compatible with any backend, from a local Ollama model to a large cloud service.

By the end of Part 5 you will have built practical tools with Apple's on-device AI framework, implemented a classical machine learning algorithm from scratch, and constructed a hybrid retrieval pipeline that bridges the gap between large document collections and small-context language models.