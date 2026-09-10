# ANSI stripping: Zunic and strip-ansi-escapes

[All Rust comparisons](../README.md)

Compare `terminal(bytes).stripAnsi(buffer)` with strip-ansi-escapes 0.2.1.
The inputs are synthetic byte fixtures in this suite's `texts/` directory.

## Run

From this directory:

```sh
make build
make test
make bench
make bench PAIRS=1
make report SUMMARY=../benchmarks/<run>/summary.json
make clean
```

See the [shared workflow](../README.md#build-test-and-benchmark) for build
settings, fetched inputs, sampling, and cleanup. Results are saved under
`../benchmarks/`; consult the report for the run you are examining.

## Timed operations

| Comparison | Zunic | Rust |
| --- | --- | --- |
| Reused output | Strip into a preallocated buffer | Construct a Writer over a reused Vec |
| Allocated output | Allocate input-sized storage, strip, consume, free | Call `strip()`, consume, free |

Both peers start from bytes and checksum every returned byte with FNV-1a.
The output byte count is reported as `units`. File reads and dump comparisons
are outside timing. No separate UTF-8 validation is added to the Rust byte API;
the parser's own decoding and re-encoding remain timed.

Each reused Rust pass constructs a fresh Writer so parser state cannot carry
between documents. Its internal allocation, flushing, and destruction remain
timed. The allocated rows use each API's normal allocation strategy, so their
allocation behavior is not identical.

## Inspect outputs

After `make build`:

```sh
./zig-out/bin/zunic-strip-ansi-bench --help
./target/release/rust-strip-ansi-bench --help
./zig-out/bin/zunic-strip-ansi-bench --dump
./target/release/rust-strip-ansi-bench texts --dump
python3 differential.py
```

Dumps identify input bytes and return `B <hex>` for the stripped bytes. The
differential checker prints readable byte representations, including escapes
and malformed UTF-8. Saved runs retain before/after dumps for both peers and
`diagnostics.json` for the diagnostic cases.

## Inputs and limits

Timed cases cover ASCII, SGR, Unicode, OSC links, command-only input, long OSC,
custom OSC, and an escape splitting a combining sequence. Their exact byte
outputs must agree before the driver accepts timings.

Separate diagnostic cases cover controls, malformed UTF-8, incomplete escapes,
DCS, C1, malformed OSC, and empty input. They are excluded from speed comparisons.
Run `make test` to see the current behavior differences rather than relying on a
saved behavior table.

Unicode property-table versions do not apply to these byte APIs. Their escape
recognition and malformed-byte policies can differ; the report records this.
The fixtures are separate from the native Zig benchmark inputs, so timings from
the two suites should not be treated as measurements of the same workload.
