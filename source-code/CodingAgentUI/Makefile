.PHONY: help build release run app open install check lint test clean diff-sources

APP_BUNDLE := build/CodingAgentUI.app
INSTALL_APP := /Applications/CodingAgentUI.app

help:
	@echo "Targets:"
	@echo "  build         debug build (swift build)"
	@echo "  release       optimized build (.build/release/CodingAgentUI)"
	@echo "  run           build and run the bare executable"
	@echo "  app           assemble build/CodingAgentUI.app around the release build"
	@echo "  open          build the .app bundle and launch it with open(1)"
	@echo "  install       build the .app bundle and copy it to /Applications"
	@echo "  test          run the CodingAgentKit tests (approval gate, events, facade)"
	@echo "  check         build; the agent runs this after every accepted edit"
	@echo "  lint          alias for check"
	@echo "  diff-sources  show drift between this kit and ../CodingCLI_swift"
	@echo "  clean         remove build artifacts"

build:
	swift build

release:
	swift build -c release

run: build
	.build/debug/CodingAgentUI

# A real .app bundle: LaunchServices then treats the process as a normal
# foreground app (Dock icon, menu bar, keyboard focus) with no help from the
# setActivationPolicy workaround in AppDelegate. This is the launch path to
# prefer; `run` works too, but only because of that workaround.
app: release
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@cp .build/release/CodingAgentUI $(APP_BUNDLE)/Contents/MacOS/CodingAgentUI
	@cp Support/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	@echo "Built $(APP_BUNDLE)"

open: app
	open $(APP_BUNDLE)

# Install for LaunchServices and the Dock. Replacing a bundle that is running
# leaves the old process alive with no bundle behind it, so quit first.
install: app
	@if pgrep -x CodingAgentUI >/dev/null; then \
		echo "CodingAgentUI is running — quit it before installing."; \
		exit 1; \
	fi
	@if [ ! -w /Applications ] || { [ -e "$(INSTALL_APP)" ] && [ ! -w "$(INSTALL_APP)" ]; }; then \
		echo "No write access to $(INSTALL_APP). Run:"; \
		echo "  sudo rm -rf $(INSTALL_APP) && sudo ditto $(APP_BUNDLE) $(INSTALL_APP)"; \
		exit 1; \
	fi
	@rm -rf "$(INSTALL_APP)"
	@ditto "$(APP_BUNDLE)" "$(INSTALL_APP)"
	@echo "Installed $(INSTALL_APP)"
	@echo "Launch it with: open $(INSTALL_APP)"

# Serial on purpose: the agent keeps its state in process-wide statics.
test:
	swift test

check: build

lint: check

# Sources/CodingAgentKit is a copy of ../CodingCLI_swift/Sources/CodingCLI with
# the terminal coupling adapted, so the two will drift as the CLI evolves.
# This shows what changed upstream; the kit's Console/Approval/facade edits are
# expected to appear in the diff.
CLI_SRC := ../CodingCLI_swift/Sources/CodingCLI

diff-sources:
	@for f in Sources/CodingAgentKit/*.swift; do \
		b=$$(basename $$f); \
		if [ -f "$(CLI_SRC)/$$b" ]; then \
			diff -u "$(CLI_SRC)/$$b" "$$f" > /dev/null 2>&1 || \
				{ echo "=== $$b ==="; diff -u "$(CLI_SRC)/$$b" "$$f" | head -60; }; \
		else \
			echo "=== $$b (kit only) ==="; \
		fi; \
	done

clean:
	rm -rf .build build
