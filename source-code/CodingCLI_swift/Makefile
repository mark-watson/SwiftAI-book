.PHONY: help build release run check lint install uninstall clean

PREFIX ?= ~
BINDIR := $(PREFIX)/bin

help:
	@echo "Targets:"
	@echo "  build      debug build (swift build)"
	@echo "  release    optimized build (.build/release/CodingCLI)"
	@echo "  run        start the CodingCLI REPL"
	@echo "  check      build; the agent runs this after every accepted edit"
	@echo "  lint       alias for check"
	@echo "  install    install the release binary to \$$(PREFIX)/bin (default /usr/local)"
	@echo "  uninstall  remove the installed binary"
	@echo "  clean      remove build artifacts"

build:
	swift build

release:
	swift build -c release

run: build
	.build/debug/CodingCLI

check: build

lint: check

install: release
	@mkdir -p $(DESTDIR)$(BINDIR)
	@install -m 0755 .build/release/CodingCLI $(DESTDIR)$(BINDIR)/CodingCLI
	@echo "Installed to $(DESTDIR)$(BINDIR)/CodingCLI"

uninstall:
	@rm -f $(DESTDIR)$(BINDIR)/CodingCLI
	@echo "Removed $(DESTDIR)$(BINDIR)/CodingCLI"

clean:
	rm -rf .build
