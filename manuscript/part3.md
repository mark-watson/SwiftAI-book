# Part 3: Deep Learning, Natural Language Processing, and Retrieval-Augmented Generation

This part moves from calling external LLM services to building AI-powered pipelines that process, understand, and retrieve information from your own data.

We open with a **deep learning introduction** — a chapter with no code that gives you the conceptual vocabulary you need for the rest of the book. You will learn how multi-layer perceptron networks are trained with backpropagation, how convolutional networks process images and text, and how more exotic architectures like autoencoders, LSTMs, and GANs fit into the modern deep learning landscape. The goal is not to make you a framework expert but to give you enough intuition to understand what is happening inside the models you will use in practice.

The **Natural Language Processing** chapter puts Apple's built-in NaturalLanguage framework through its paces. We build a utility library (`Nlp_swift`) that wraps five key NLP capabilities, all of which run entirely on-device with no network calls:

- **Named Entity Recognition** — identifying people, places, and organizations in text using `NLTagger`
- **Lemmatization** — reducing words to their dictionary base forms ("went" → "go")
- **Language Detection** — identifying the dominant language of any text passage across 50+ languages
- **Sentiment Analysis** — scoring text from -1.0 (very negative) to 1.0 (very positive), at both the document and sentence level
- **Word Embeddings** — finding semantically similar words using Apple's pre-trained `NLEmbedding` vectors

These are fast, private, and available offline — perfect for building features that need to work without an internet connection.

Part 3 culminates in a hands-on **Document Question Answering** chapter that implements a complete Retrieval-Augmented Generation (RAG) pipeline in Swift. You will build four components from scratch: a sentence-aware text chunker (using `NLTokenizer`), a Gemini Embedding API client that converts text chunks into 3072-dimensional vectors, an in-memory vector store with cosine similarity search, and a question-answering module powered by Gemini Flash. The system ingests a directory of text files, indexes them, and then answers natural-language questions grounded in the actual document content — reducing the hallucination problem that plagues standalone LLMs.

By the end of Part 3 you will understand the principles behind deep learning, know how to use Apple's on-device NLP models for practical text processing, and have built a working RAG system that you can adapt to your own document collections.