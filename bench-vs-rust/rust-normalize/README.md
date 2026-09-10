# Normalization: Zunic and unicode-normalization

[All Rust comparisons](../README.md)

Compare `text(bytes).normalize(form)` for all four forms -- `.nfc`, `.nfd`,
`.nfkc`, `.nfkd` -- with unicode-normalization 0.1.24 using the shared texts
in `../texts/`.

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

Both peers iterate normalized scalars for all four forms, count them, and
compute a wrapping u64 sum. Timing includes UTF-8 validation, decoding, and
scalar iteration. It excludes output UTF-8 encoding, file I/O, and caller
output allocation. This does not benchmark `writeTo()` or normalization
queries. NFKC and NFKD use the same corpora as NFC and NFD, none of which are
adversarially chosen for compatibility expansion; they exercise ordinary
compatibility-mapping density in real text, not the worst-case 18-scalar
expansion the native suite (`zig build benchmark`) covers separately.

Rust validates raw bytes inside each timed pass and may allocate internal
combining buffers. Zunic uses its configured bounded buffer. See the
[normalization limits](../../docs/text/normalization/README.md#combining-run-limit)
for Zunic's buffer contract. The shared corpora are not a stress test of that
limit or malformed-input handling.

## Inspect outputs

After `make build`:

```sh
./zig-out/bin/zunic-normalize --help
./target/release/unicode-normalization-zunic --help
./zig-out/bin/zunic-normalize --dump
./target/release/unicode-normalization-zunic ../texts --dump
python3 differential.py
```

Each dump record contains `case`, `form`, `input` (hex), and `hex` (normalized
UTF-8 bytes). Saved runs keep before/after dumps for each peer. The driver
compares normalized bytes separately per form -- never across forms -- and
checks the timed scalar count/sum against them. Output encoding is performed
for verification outside the timed iterator workload.

## Versions and limits

Both peers use Unicode 16.0.0. `make test` runs local regression checks and a
Rust check against the repository's pinned normalization fixture, then compares
the shared corpus outputs. Consult the run output for agreement; fixture counts
and historical pass summaries are not benchmark results.

A separate diagnostic excludes Rust's UTF-8 validation while Zunic still
validates its input:

```sh
python3 benchmark.py --rust-input prevalidated --label normalize-prevalidated
```

Its different input contract is labelled in the report. Use the default byte
mode for the primary comparison.
