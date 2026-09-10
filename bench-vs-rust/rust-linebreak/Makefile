ZIG ?= zig
CARGO ?= cargo
PYTHON ?= python3
OPTIMIZE ?= ReleaseFast
CPU ?= native
RUSTFLAGS ?= -C target-cpu=native
PAIRS ?= 3
LABEL ?= rust-machine
SUMMARY ?=

.PHONY: all build test bench report clean

all: build test

build:
	$(PYTHON) ../build_inputs.py
	$(ZIG) build install-diagnostic -Doptimize=$(OPTIMIZE) -Dcpu=$(CPU) --summary all
	RUSTFLAGS='$(RUSTFLAGS)' $(CARGO) build --locked --release --manifest-path diagnostic-rust/Cargo.toml

test: build
	$(ZIG) build verify-semantic -Doptimize=ReleaseSafe -Dcpu=$(CPU) --summary all
	RUSTFLAGS='$(RUSTFLAGS)' $(CARGO) test --locked --release --manifest-path diagnostic-rust/Cargo.toml
	$(PYTHON) benchmark-rust-machine.py --self-test

bench: build
	$(PYTHON) benchmark-rust-machine.py --pairs $(PAIRS) --label $(LABEL)

report:
	@test -n "$(SUMMARY)" || { echo "usage: make report SUMMARY=path/to/summary.json" >&2; exit 2; }
	$(PYTHON) ../benchmark_report.py $(SUMMARY)

clean:
	rm -rf target diagnostic-rust/target zig-out .zig-cache .zig-global-cache __pycache__
