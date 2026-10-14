.PHONY: help build release models models-py train run run-tensor run-plan run-stateful run-rag run-rag-no-llm check lint clean clean-all

help:
	@echo "Targets:"
	@echo "  build            debug build (swift build)"
	@echo "  release          optimized build (swift build -c release)"
	@echo "  models           build and train all models (python + TrainModels)"
	@echo "  models-py        build Core ML models from Hugging Face via python/make_models.py"
	@echo "  train            train Create ML models via TrainModels"
	@echo "  run              run LocalRAG capstone example"
	@echo "  run-tensor       run TensorBasics example"
	@echo "  run-plan         run ComputePlanInspector example"
	@echo "  run-stateful     run StatefulGeneration example"
	@echo "  run-rag          run LocalRAG capstone example"
	@echo "  run-rag-no-llm   run LocalRAG without LLM"
	@echo "  check            debug build; check all targets compile"
	@echo "  lint             alias for check"
	@echo "  clean            remove .build artifacts and compiled model cache"
	@echo "  clean-all        remove .build artifacts and all generated models"

build:
	swift build

release:
	swift build -c release

models-py:
	uv run python/make_models.py

train: release
	swift run -c release TrainModels

models: models-py train

run: run-rag

run-tensor: release
	swift run -c release TensorBasics

run-plan: build
	swift run ComputePlanInspector

run-stateful: release
	swift run -c release StatefulGeneration "Sport is"

run-rag: release
	swift run -c release LocalRAG

run-rag-no-llm: release
	swift run -c release LocalRAG --no-llm "What do economists study?"

check: build

lint: check

clean:
	rm -rf .build models/compiled

clean-all:
	rm -rf .build models
