# Terminal benchmarks

[Terminal API](README.md) · [Implementation](implementation.md)

The native suite includes `terminal_tokens` and `strip_ansi` rows. Run all
operations with `make bench`, or just the terminal cases with:

```sh
make bench BENCHMARK_ARGS=--terminal
make bench BENCHMARK_ARGS='--terminal --smoke'
```

The smoke run checks execution and output; use full runs for performance.
Each full sample processes about 4 MiB of input, with seven samples after a
warm-up. Corpora and the strip output buffer are prepared outside timing.
The input is a runtime byte slice, including for malformed-input cases.

Token checksums include token kind, escape kind, and byte offsets. The expected
error case must raise `EscapeInsideGrapheme`; unexpected failures abort the run.
Stripping checksums include every output byte and its length. Checksumming is
inside the timed loop, matching the existing native suite. These are traversal
and output-consumption measurements, not isolated function-call timings.

The cases cover plain ASCII at 4 KiB and 64 KiB, sparse/dense SGR, combining
marks and emoji, OSC links, escape-only input, malformed bytes and sequences,
long complete/unterminated OSC, and an escape inside a grapheme at the end of
input. Ordinary repeated seeds are kept whole to avoid accidental truncation.
Throughput counts input bytes even when stripping produces little or no output.

## Save and compare

```sh
make benchmark-save BENCHMARK_LABEL=terminal-before BENCHMARK_ARGS='-- --terminal'
# Make the change, then repeat with identical build settings:
make benchmark-save BENCHMARK_LABEL=terminal-after BENCHMARK_ARGS='-- --terminal'
make benchmark-compare BEFORE=private/benchmarks/<before-run> AFTER=private/benchmarks/<after-run>
```

The extra `--` in save commands separates the history script's arguments from
the benchmark's arguments. Each save prints its archive directory. Archives
contain raw samples, medians, sample spread, checksums, compiler and machine
information, Git revision, and a fingerprint of the current sources, including
uncommitted changes. They are local files under ignored `private/benchmarks/`.

Compare matching compiler, machine, arguments, and build settings. Positive
`change_percent` means slower; `output-changed` requires investigation regardless
of timing. Investigate a slowdown above 5% that repeats across runs. High sample
spread or disagreement between unchanged runs calls for another measurement on
an idle machine, not an immediate regression verdict. There is no automatic
timing gate on shared CI hardware.

Harness version 10 introduces these rows. Earlier harness archives cannot be
compared by the history script; retain this version as the terminal baseline.
Future changes to case contents or checksum definitions require a new harness
version rather than silently replacing an existing measurement.

## Initial baseline — 2026-09-09

Zig 0.16.0, ReleaseFast, macOS 26.6.2 on arm64, default build settings.
The source revision was `9a394bb` plus the new benchmark harness; the archives
record the dirty state and source fingerprint and include the benchmark source,
terminal source, and source diff. No library implementation changed for this run.

Baseline: `private/benchmarks/20260909T201843Z-terminal-baseline-417b81`.
Repeat: `private/benchmarks/20260909T201905Z-terminal-baseline-repeat-61f1b3`.

Both runs have 22 rows with seven samples each. Checksums match within and
between runs. All median changes were within 5% (largest absolute change: 4.61%).
The table shows first-run median input throughput in MiB/s, including checksum
work. These numbers are a machine-specific reference, not a cross-machine target.

| Case | Tokens MiB/s | Strip ANSI MiB/s |
| --- | ---: | ---: |
| `term-commands-only` | 1161.9 | 2447.8 |
| `term-dense-sgr` | 650.9 | 2451.6 |
| `term-long-osc` | 1589.0 | 1610.3 |
| `term-malformed` | 197.5 | 839.2 |
| `term-osc` | 515.1 | 1543.2 |
| `term-plain-ascii` | 152.5 | 681.5 |
| `term-plain-ascii-64k` | 152.4 | 666.2 |
| `term-sparse-sgr` | 165.4 | 690.6 |
| `term-split-grapheme` | 158.3 | 665.1 |
| `term-unicode` | 371.4 | 772.1 |
| `term-unterminated-osc` | 131.1 | 478.5 |
