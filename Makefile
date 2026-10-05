ZIG ?= zig
PYTHON ?= python3
OPTIMIZE ?= ReleaseFast
BENCHMARK_ARGS ?=
BENCHMARK_BUILD_ARGS ?=

.DEFAULT_GOAL := all
.PHONY: all build test docs-test bench benchmark benchmark-save benchmark-compare verify-tables test-tools

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
	ZUNIC_BENCHMARK_BUILD_ARGS='$(BENCHMARK_BUILD_ARGS)' $(PYTHON) src/tools/benchmark-history.py save --zig "$(ZIG)" --optimize "$(OPTIMIZE)" --label $${BENCHMARK_LABEL:?set BENCHMARK_LABEL} -- $(BENCHMARK_ARGS)

benchmark-compare:
	$(PYTHON) src/tools/benchmark-history.py compare --before $${BEFORE:?set BEFORE} --after $${AFTER:?set AFTER}

# Maintainer checks are separate from the Python-free Zig test suite.
verify-tables:
	$(PYTHON) src/tools/test-properties.py
	$(PYTHON) src/tools/test-terminal-properties.py
	$(PYTHON) src/tools/test-word-properties.py
	$(PYTHON) src/tools/test-normalization-properties.py
	$(PYTHON) src/tools/test-case-folding.py
	$(PYTHON) src/tools/test-simple-case-mappings.py
	$(PYTHON) src/tools/test-numeric-properties.py
	$(PYTHON) src/tools/test-script-properties.py
	$(PYTHON) src/tools/test-bidi-properties.py
	$(PYTHON) src/tools/test-general-category.py
	$(PYTHON) src/tools/test-line-break-machine.py

test-tools:
	$(PYTHON) src/tools/test-benchmark-history.py
	$(PYTHON) bench-vs-uucode/test-benchmark.py
