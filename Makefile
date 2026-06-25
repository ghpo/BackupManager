# =============================================================================
# bhm — Backup Home Manager Makefile
# =============================================================================

SHELL := /bin/bash
BHM_HOME := $(CURDIR)
INSTALL_PREFIX ?= /usr/local
BATS ?= bats

.PHONY: help install uninstall test check format clean lint

help:
	@echo "bhm — Backup Home Manager"
	@echo ""
	@echo "Targets:"
	@echo "  install     Install bhm and libraries to \$${PREFIX:-/usr/local}"
	@echo "  uninstall   Remove bhm and libraries"
	@echo "  test        Run Bats test suite"
	@echo "  lint        Run ShellCheck on all scripts"
	@echo "  check       Run lint + test"
	@echo "  format      Format shell scripts with shfmt (if available)"
	@echo "  clean       Remove temporary files"

install:
	@echo "Installing bhm to $(INSTALL_PREFIX)..."
	install -d "$(INSTALL_PREFIX)/bin"
	install -d "$(INSTALL_PREFIX)/lib/bhm"
	install -m 755 bhm "$(INSTALL_PREFIX)/bin/bhm"
	install -m 644 lib/*.sh "$(INSTALL_PREFIX)/lib/bhm/"
	install -d "$(DESTDIR)/etc/bhm"
	install -m 644 etc/bhm.conf "$(DESTDIR)/etc/bhm/bhm.conf"
	@echo "Done. Run 'bhm help' to get started."

uninstall:
	@echo "Removing bhm from $(INSTALL_PREFIX)..."
	rm -f "$(INSTALL_PREFIX)/bin/bhm"
	rm -rf "$(INSTALL_PREFIX)/lib/bhm"
	rm -f "$(DESTDIR)/etc/bhm/bhm.conf"
	@echo "User config at ~/.config/bhm/bhm.conf was NOT removed."

test:
	@if ! command -v $(BATS) &>/dev/null; then \
		echo "ERROR: 'bats' not found. Install it first."; \
		exit 1; \
	fi
	cd "$(BHM_HOME)" && ./tests/run_tests.sh

lint:
	@if ! command -v shellcheck &>/dev/null; then \
		echo "ERROR: 'shellcheck' not found. Install it first."; \
		exit 1; \
	fi
	shellcheck --shell=bash --external-sources --severity=style \
		bhm lib/*.sh tests/run_tests.sh
	@echo "ShellCheck passed."

check: lint test

format:
	@if command -v shfmt &>/dev/null; then \
		shfmt -i 2 -ci -sr -w bhm lib/*.sh tests/run_tests.sh tests/bats/*.bash tests/bats/*.bats; \
		echo "Formatted with shfmt."; \
	else \
		echo "shfmt not found. Install it: go install mvdan.cc/sh/v3/cmd/shfmt@latest"; \
	fi

clean:
	rm -rf tests/reports
	find . -name '*.log' -path '*/bhm/*' -delete || true
	@echo "Cleaned."
