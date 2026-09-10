# Line breaking: Zunic and unicode-linebreak

[All Rust comparisons](../README.md)

Compare Zunic's line-break opportunity iterator with unicode-linebreak 0.1.5
using the eight shared texts in `../texts/`.

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

The direct comparison is `opportunities_only`: traverse allowed and mandatory
breaks, count them, and checksum byte offsets and statuses. Rust validates raw
bytes inside each timed pass. File I/O and exact-output checks are outside
timing. Barriers protect input and final results without blocking each boundary.

The executable also emits diagnostic timings for classification. Zunic has
additional rows for all boundaries, preclassified transitions, full wrapping,
and first-24-line wrapping. These rows are separate measurements; they are not
interchangeable with the direct opportunity comparison or additive costs.

## Inspect outputs

After `make build`:

```sh
./zig-out/bin/line-break-diagnostic --help
./diagnostic-rust/target/release/diagnostic --help
./zig-out/bin/line-break-diagnostic --dump
./diagnostic-rust/target/release/diagnostic ../texts --dump
```

Dumps identify input bytes and list `offset:allowed` or `offset:mandatory`
events. `--streams` is an alias for `--dump`. Saved runs keep
`zunic-streams-before.txt`, `rust-streams-before.txt`, and after-run streams.
The driver compares the ordered events and checks each timed result against
that peer's stream.

## Versions and limits

Zunic uses Unicode 16.0.0. The Rust crate uses Unicode 15.0.0 and resolves some
script-dependent line-break classes differently. Reports state both versions
and show actual output agreement. Neither a count match nor a version mismatch
alone explains a boundary difference.

## Untimed diagnostics

```sh
zig build verify-semantic -Doptimize=ReleaseSafe
zig build semantic-stats -Doptimize=ReleaseFast
python3 benchmark-rust-machine.py --self-test
```

`verify-semantic` compares Zunic's iterator with its direct machine protocol on
the corpora and edge cases. Both use the same implementation, so this checks
integration rather than independent Unicode semantics. `semantic-stats` prints
state sizes, actions, and lookahead counters. The build steps supply `--check`
and `--stats` respectively; running either helper without arguments prints help.
