.PHONY: benchmark benchmark-save

BENCHMARK_ARGS ?=

benchmark:
	zig build benchmark -Doptimize=ReleaseFast -- $(BENCHMARK_ARGS)

benchmark-save:
	mkdir -p private/benchmarks
	zig build benchmark -Doptimize=ReleaseFast -- $(BENCHMARK_ARGS) > private/benchmarks/$$(git rev-parse --short HEAD).txt
