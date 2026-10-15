.PHONY: help all build release run test simulate check lint install uninstall clean

PREFIX ?= ~
BINDIR := $(PREFIX)/bin

help:
	@echo "Targets:"
	@echo "  build      debug build (swift build)"
	@echo "  release    optimized build (.build/release/bridge)"
	@echo "  run        start the WebKit Bridge game"
	@echo "  test       run test suite and simulations (swift test)"
	@echo "  simulate   run headless 20-rubber simulation"
	@echo "  check      build and test"
	@echo "  lint       alias for check"
	@echo "  install    install the release binary to \$$(PREFIX)/bin (default ~/bin)"
	@echo "  uninstall  remove the installed binary"
	@echo "  clean      remove build artifacts"

all: build

build:
	swift build

release:
	swift build -c release

run:
	swift run bridge

test:
	swift test

simulate:
	swift run bridge --simulate

check: build test

lint: check

install: release
	@mkdir -p $(DESTDIR)$(BINDIR)
	@install -m 0755 .build/release/bridge $(DESTDIR)$(BINDIR)/bridge
	@echo "Installed to $(DESTDIR)$(BINDIR)/bridge"

uninstall:
	@rm -f $(DESTDIR)$(BINDIR)/bridge
	@echo "Removed $(DESTDIR)$(BINDIR)/bridge"

clean:
	swift package clean
	rm -rf .build
