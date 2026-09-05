.PHONY: benchmark

BENCHMARK_ARGS ?=

benchmark:
	zig build benchmark -Doptimize=ReleaseFast -- $(BENCHMARK_ARGS)
