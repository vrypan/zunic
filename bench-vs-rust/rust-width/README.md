# Display width: Zunic and unicode-width

[All Rust comparisons](../README.md)

Compare `text(bytes).width()` with unicode-width 0.2.2 using the shared texts
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

| Zunic | Rust | Work performed |
| --- | --- | --- |
| `zunic_width` | `unicode_width_str` | Whole-text display width |

`Text.width()` and `str::width()` are each peer's one public entry point for
this measurement, so this suite has a single comparison row, the same shape
as [line breaking](../rust-linebreak/README.md).

Zunic measures whole grapheme clusters: a base letter plus its combining
marks, or a multi-scalar emoji sequence, counts once. unicode-width sums
per-`char` widths, adjusted for a handful of context-sensitive cases such as
Arabic joining transparency -- it is not a naive per-scalar sum, but it is
still not grapheme-cluster aware. The two policies agree only for text with
no combining marks, no joining behavior, and no multi-scalar clusters;
corpora that have them are expected to disagree, and that disagreement is
reported rather than hidden. This is a difference in what "width" means, not
a bug in either peer.

Every shared corpus differs in practice, for two separate reasons. Scripts
with combining marks or Arabic joining (`arabic`, `hindi`, `korean`,
`russian`, `japanese`, `mandarin`) differ per the cluster-versus-char policy
above. The mostly-ASCII corpora (`english`, `source_code`) differ by exactly
their newline-plus-tab byte count: unicode-width counts `\n` and `\t` as one
column each, while Zunic's width policy drops control characters entirely,
matching its terminal-filtering contract. Confirmed by exact arithmetic
match against each corpus's control-byte count, not assumed.

An unexposed second Zig code path (`graphemesWidth` in `zunic-width.zig`,
covered by `zig build test`) sums the same grapheme measurements through the
public per-cluster iterator instead of `Text.width()`'s internal fast path,
as an internal consistency check; the earlier design tried to pair it with a
hand-written Rust per-char loop, but that loop is a different algorithm from
`str::width()`, not just a different code path, so it did not belong in the
cross-peer comparison and was removed.

Both peers validate/decode UTF-8 inside timing. File I/O is excluded.

## Inspect outputs

After `make build`:

```sh
./zig-out/bin/zunic-width-bench --help
./target/release/unicode-width-bench --help
./zig-out/bin/zunic-width-bench --dump
./target/release/unicode-width-bench ../texts --dump
```

Each dump record contains `case`, `input` (hex), and `width` (decimal). Saved
runs keep before/after dumps for each peer; the driver checks the timed
checksum and unit count for both operations against this value and reports
the run unchanged if it moved between them.

## Versions and limits

Zunic uses Unicode 16.0.0. unicode-width 0.2.2 uses Unicode 17.0.0. Version and
cluster-vs-char policy differences are accepted constraints on the "same"/"diff"
column; they are not automatically a Zunic bug or a Rust bug.

`cellwidth` is a separate, unrelated crate compared for full-document
wrapping in [`../rust-wrap`](../rust-wrap/README.md#versions-and-limits),
retained there behind an optional feature and excluded from that suite's
default build. This suite is not related to that comparison.
