.PHONY: benchmark benchmark-save benchmark-compare

BENCHMARK_ARGS ?=
BENCHMARK_BUILD_ARGS ?=

benchmark:
	zig build benchmark -Doptimize=ReleaseFast $(BENCHMARK_BUILD_ARGS) -- $(BENCHMARK_ARGS)

benchmark-save:
	ZUNIC_BENCHMARK_BUILD_ARGS='$(BENCHMARK_BUILD_ARGS)' python3 src/tools/benchmark-history.py save --label $${BENCHMARK_LABEL:?set BENCHMARK_LABEL} $(BENCHMARK_ARGS)

benchmark-compare:
	python3 src/tools/benchmark-history.py compare --before $${BEFORE:?set BEFORE} --after $${AFTER:?set AFTER}
