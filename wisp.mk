# Wisp tasks. `make` lists them; logic lives in dist/wisp/wisp.sh.
# DRY_RUN=1 shows what sync and release would do.

WISP := dist/wisp/wisp.sh

help:
	@echo "Wisp:"
	@echo "  make build       signed local build (zig-out/Wisp.app)"
	@echo "  make run         build and restart the local Wisp"
	@echo "  make test        Python, Swift and Zig tests (Zig is slow)"
	@echo "  make test-quick  Python and Swift tests"
	@echo "  make sync        merge Ghostty main, push (makes a tip build)"
	@echo "  make push        push downstream (makes a tip build)"
	@echo "  make release     merge Ghostty's newest release, tag vX.Y.Z-wisp.N, push"
	@echo "  make status      versions, published releases, recent runs"
	@echo "  make docs        preview the reference site locally"
	@echo "  make watch       follow the newest workflow run"
.PHONY: help

build run test test-quick sync push release status docs watch:
	@$(WISP) $@
.PHONY: build run test test-quick sync push release status docs watch
