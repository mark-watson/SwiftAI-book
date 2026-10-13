# Core ML and Create ML: Example for Mark Watson's book "Artificial Intelligence Using Swift"

Book URI: https://leanpub.com/SwiftAI

You can read my book for free online at: https://leanpub.com/SwiftAI/read

Code-first Create ML training and Core ML inference on Apple Silicon. Every model is built by a script or a Swift program, so you can keep the whole pipeline in version control and rebuild it from the command line.

Requirements: macOS 26 or later, Xcode 26 or later (Swift 6.2), and [uv](https://docs.astral.sh/uv/) for the Python conversion script. The LocalRAG example uses Apple Intelligence when it is on; without it, LocalRAG prints the best passage instead.

## Build the models

The git repo holds no models. The `models` directory (about 220 MB) is in `.gitignore`, so you must build it once before you run any example. Run these two commands from this directory, in this order:

    uv run python/make_models.py      # about 1 minute
    swift run -c release TrainModels  # about 15 seconds

The first command downloads one model from Hugging Face and converts it. Everything else gets trained on your Mac, and nothing else is downloaded.

| File in `models/` | Size | Made by | Source |
|---|---|---|---|
| `MiniLMEmbedding.mlpackage` | 22 MB | `make_models.py` | Downloaded: [sentence-transformers/all-MiniLM-L6-v2](https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2), converted with int8 weights |
| `MiniLMEmbeddingFlexible.mlpackage` | 86 MB | `make_models.py` | Same download, float32, flexible length (used only by ComputePlanInspector) |
| `minilm_vocab.txt` | 228 KB | `make_models.py` | Tokenizer vocabulary from the same download |
| `CharLM.mlpackage` | 1 MB | `make_models.py` | Trained locally on `../data/*.txt` |
| `charlm_vocab.json` | 4 KB | `make_models.py` | Character list for CharLM |
| `TopicRouter.mlmodel` | 2 MB | `TrainModels` | Trained locally with Create ML on `training/router_queries.csv` and `../data/*.txt` |
| `CancerClassifier.mlpackage` | 16 KB | `TrainModels` | Trained locally with CreateMLComponents on `training/wisconsin_cancer.csv` |
| `compiled/*.mlmodelc` | 110 MB | first run of any example | Compiled copies that Core ML loads; deleting them is safe |

The Hugging Face download is about 90 MB and goes to `~/.cache/huggingface`. If your shell sets `HF_HUB_ENABLE_HF_TRANSFER=1` and you don't have the `hf_transfer` package installed, the download fails. Run the script with that variable unset:

    env -u HF_HUB_ENABLE_HF_TRANSFER uv run python/make_models.py

Which examples need which models:

| Example | Needs |
|---|---|
| `TensorBasics` | MiniLMEmbedding |
| `ComputePlanInspector` | Any model present (skips missing ones) |
| `StatefulGeneration` | CharLM |
| `LocalRAG` | MiniLMEmbedding and TopicRouter |

If a model is missing, the example tells you which command to run. To start over, delete `models/` and run both commands again.

## Run the examples

    swift run -c release TensorBasics
    swift run ComputePlanInspector
    swift run ComputePlanInspector MiniLMEmbedding.mlpackage --units cpuAndNeuralEngine --verbose
    swift run -c release StatefulGeneration "Sport is"
    swift run -c release LocalRAG
    swift run -c release LocalRAG --no-llm "What do economists study?"

## Files

| File | Description |
|---|---|
| `python/make_models.py` | Converts all-MiniLM-L6-v2 to Core ML (int8 fixed shape, and a float32 flexible shape variant), trains a tiny character LM, and saves it as a two function model (stateful `generate`, stateless `score`) |
| `Sources/TrainModels/main.swift` | Create ML `MLTextClassifier` topic router; CreateMLComponents logistic regression and fully connected classifiers on the Wisconsin cancer data, with Core ML export |
| `Sources/TensorBasics/main.swift` | `MLTensor` operations, cosine search, `withMLTensorComputePolicy`, sequential and concurrent async predictions |
| `Sources/ComputePlanInspector/main.swift` | `MLComputePlan` report: per op device choice, estimated cost, and ops that miss the Neural Engine |
| `Sources/StatefulGeneration/main.swift` | KV-cache generation with `MLState`, function selection with `functionName`, log-probability scoring |
| `Sources/LocalRAG/main.swift` | Capstone: Create ML router and guardrail, Core ML retrieval, Foundation Models answer |
| `Sources/MLSupport/` | Model compile cache, WordPiece tokenizer, concurrent `Embedder`, document chunking, seeded RNG |
| `training/` | Router training queries and the Wisconsin cancer CSV |

## Known issue

On macOS 27.0.1 with coremltools 9.0, Core ML refuses to load any stateful model (error -14), including the accumulator example from the coremltools docs. `StatefulGeneration` reports the error and falls back to the stateless `score` function. `make_models.py` checks in PyTorch that the KV-cache logic matches a full forward pass.

## Book Cover Material, Copyright, and License

This example is released using the Apache 2 license.

Copyright 2022-2026 Mark Watson. All rights reserved.

## This Book is Licensed with Creative Commons Attribution CC BY Version 3 That Allows Reuse In Derived Works

You are free to:

- Share: copy and redistribute the material in any medium or format
- Adapt: remix, transform, and build upon the material
for any purpose, even commercially.

You are required to give appropriate credit in any derived works:

```text
This work is derived from all or part of "Artificial Intelligence Using Swift" by
Mark Watson. Source: https://leanpub.com/SwiftAI
```

Please visit the [author's website](http://markwatson.com).
