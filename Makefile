ZIG ?= zig
PYTHON ?= python3
OPTIMIZE ?= ReleaseFast
BENCHMARK_ARGS ?=
BENCHMARK_BUILD_ARGS ?=

.DEFAULT_GOAL := all
.PHONY: all build test docs-test bench benchmark benchmark-save benchmark-compare

all: build test

build:
	$(ZIG) build --summary all

test:
	$(ZIG) build test --summary all

docs-test:
	$(ZIG) build docs-test --summary all

bench benchmark:
	$(ZIG) build benchmark -Doptimize=$(OPTIMIZE) $(BENCHMARK_BUILD_ARGS) -- $(BENCHMARK_ARGS)

benchmark-save:
	ZUNIC_BENCHMARK_BUILD_ARGS='$(BENCHMARK_BUILD_ARGS)' $(PYTHON) src/tools/benchmark-history.py save --label $${BENCHMARK_LABEL:?set BENCHMARK_LABEL} $(BENCHMARK_ARGS)

benchmark-compare:
	$(PYTHON) src/tools/benchmark-history.py compare --before $${BEFORE:?set BEFORE} --after $${AFTER:?set AFTER}
