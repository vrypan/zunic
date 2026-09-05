.PHONY: benchmark benchmark-save benchmark-compare

BENCHMARK_ARGS ?=

benchmark:
	zig build benchmark -Doptimize=ReleaseFast -- $(BENCHMARK_ARGS)

benchmark-save:
	python3 src/tools/benchmark-history.py save --label $${BENCHMARK_LABEL:?set BENCHMARK_LABEL} $(BENCHMARK_ARGS)

benchmark-compare:
	python3 src/tools/benchmark-history.py compare --before $${BEFORE:?set BEFORE} --after $${AFTER:?set AFTER}
