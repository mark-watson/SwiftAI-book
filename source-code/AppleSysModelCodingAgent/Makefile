.PHONY: help build release run install check lint test clean

NAME := AppleSysModelCodingAgent
BINDIR ?= $(HOME)/bin

help:
	@echo "Targets:"
	@echo "  build         debug build (swift build)"
	@echo "  release       optimized build (.build/release/$(NAME))"
	@echo "  run           build and start the agent in this directory (ARGS=\"-C ~/proj\")"
	@echo "  install       copy the release binary to $(BINDIR) (BINDIR=...)"
	@echo "  test          run the CodingAgentKit tests"
	@echo "  check         build; the agent runs this after every accepted edit"
	@echo "  lint          alias for check"
	@echo "  clean         remove build artifacts"

build:
	swift build

release:
	swift build -c release

run: build
	.build/debug/$(NAME) $(ARGS)

install: release
	@mkdir -p "$(BINDIR)"
	@cp .build/release/$(NAME) "$(BINDIR)/$(NAME)"
	@echo "Installed $(BINDIR)/$(NAME)"
	@case ":$$PATH:" in *":$(BINDIR):"*) ;; *) echo "Note: $(BINDIR) is not on your PATH." ;; esac

# Serial on purpose: the agent keeps its state in process-wide statics.
test:
	swift test

check: build

lint: check

clean:
	rm -rf .build
