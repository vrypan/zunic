ZIG ?= zig
PYTHON ?= python3
OPTIMIZE ?= ReleaseFast
CPU ?= native
PAIRS ?= 3
OPERATIONS ?= all
LABEL ?= uucode
SUMMARY ?=

.DEFAULT_GOAL := all
.PHONY: all build test bench report clean

all: test

build:
	$(PYTHON) ../bench-vs-rust/build_inputs.py
	$(ZIG) build -Doptimize=$(OPTIMIZE) -Dcpu=$(CPU) --summary all

test: build
	$(ZIG) build test -Doptimize=$(OPTIMIZE) -Dcpu=$(CPU) --summary all
	$(PYTHON) benchmark.py --self-test

bench: build
	$(PYTHON) benchmark.py --pairs $(PAIRS) --label $(LABEL) --skip-build --operations "$(OPERATIONS)"

report:
	@test -n "$(SUMMARY)" || { echo "usage: make report SUMMARY=path/to/summary.json" >&2; exit 2; }
	$(PYTHON) benchmark.py --report $(SUMMARY)

clean:
	rm -rf zig-out .zig-cache .zig-global-cache __pycache__
