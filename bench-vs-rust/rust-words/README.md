# Word boundaries: Zunic and unicode-segmentation

[All Rust comparisons](../README.md)

Compare `text(bytes).wordBounds()` with unicode-segmentation 1.13.3 using
the eight shared texts in `../texts/`.

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

| Zunic | Rust | Work performed |
| --- | --- | --- |
| `zunic_word_bounds` | `us_word_bounds` | Traverse every segment's byte range |
| `zunic_word_bounds_collect` | `us_word_bounds_collect` | Collect and consume borrowed segment records |
| `zunic_words` | `us_words` | Traverse word-like segments only |

Rust uses `split_word_bound_indices()` for all boundaries and
`unicode_word_indices()` for words. Zunic filters its `WordBound.is_word`
field. Each pass starts from bytes; Rust validates UTF-8 inside timing.
Both sides count ranges and checksum their start/end offsets. Collection rows
include allocation and destruction, without copying the underlying text.

## Inspect outputs

After `make build`:

```sh
./zig-out/bin/zunic-words-bench --help
./target/release/unicode-words-bench --help
./zig-out/bin/zunic-words-bench --dump
./target/release/unicode-words-bench ../texts --dump
python3 differential.py
```

Dumps identify each corpus and its input bytes. `S <start> <end> <flag>` records
a half-open byte range and whether it is word-like. The differential checker
prints mismatched boundaries and flags with surrounding text. Saved runs keep
`zunic-before.dump`, `rust-before.dump`, and after-run dumps.

The Rust adapter gets word flags by matching the crate's word iterator against
its full partition. It does not substitute Rust's standard-library character
predicates, which could use different Unicode data.

## Versions and limits

Zunic uses Unicode 16.0.0; unicode-segmentation uses 17.0.0. Reports compare full
partitions and filtered word ranges separately. Equal segment counts alone do
not establish agreement. Differences are reported, not assumed to be bugs.

Optional property diagnostics:

```sh
python3 differential.py --verify
python3 differential.py --verify --strict
python3 test_differential.py
```

`--verify` fetches missing Unicode fixtures and examines property changes.
`--strict` fails if a difference remains unexplained. `--max-report` limits
printed details, not verification. Property changes are clues; context and rule
changes can also affect boundaries. No fixed agreement count is promised here.
