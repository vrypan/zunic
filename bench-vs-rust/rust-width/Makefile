ZIG ?= zig
CARGO ?= cargo
PYTHON ?= python3
OPTIMIZE ?= ReleaseFast
CPU ?= native
RUSTFLAGS ?= -C target-cpu=native
PAIRS ?= 3
LABEL ?= unicode-width-zunic
SUMMARY ?=

.PHONY: all build test bench report clean

all: build test

build:
	$(PYTHON) ../build_inputs.py
	$(ZIG) build -Doptimize=$(OPTIMIZE) -Dcpu=$(CPU) --summary all
	RUSTFLAGS='$(RUSTFLAGS)' $(CARGO) build --locked --release

test: build
	RUSTFLAGS='$(RUSTFLAGS)' $(CARGO) test --locked --release
	$(ZIG) build test -Doptimize=$(OPTIMIZE) -Dcpu=$(CPU) --summary all

bench: build
	$(PYTHON) benchmark.py --pairs $(PAIRS) --label $(LABEL)

report:
	@test -n "$(SUMMARY)" || { echo "usage: make report SUMMARY=path/to/summary.json" >&2; exit 2; }
	$(PYTHON) ../benchmark_report.py $(SUMMARY)

clean:
	rm -rf target zig-out .zig-cache .zig-global-cache __pycache__
