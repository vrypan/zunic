# uucode comparison benchmarks

Compare the current Zunic working tree with
[uucode 0.2.0](https://github.com/jacobsandlund/uucode) at pinned commit
`f67fa5dbef5c9de57773dbe2f7a02bebc7e20301`. Both peers are Zig libraries and
are built with the same Zig version, target, optimization mode, and CPU model.
The dependency hash in `build.zig.zon` verifies the fetched package.

uucode and Zunic overlap in four bytes-to-results operations:

| Operation | Zunic | uucode | Timed result consumed |
|---|---|---|---|
| UTF-8 decoding | `zunic.utf8.step` | `uucode.utf8.Iterator` | code point and ending byte offset |
| Grapheme segmentation | `text(...).graphemes()` | `grapheme.utf8Iterator` | every start/end byte range |
| Measured graphemes | measured grapheme iterator | `grapheme.wcwidthNext` | every start/end range and cluster width |
| Whole-text width | `text(...).width()` | `grapheme.utf8Wcwidth` | total columns |

uucode does not currently expose comparable line breaking, normalization,
word boundaries, wrapping, or ANSI stripping, so those Zunic features are not
included. The shared corpora are the same eight multilingual files used by
`bench-vs-rust`; the suite checks them before use and embeds them into both
executables.

## Run it

From this directory:

```sh
make build
make test
make bench
```

`make bench PAIRS=1` is useful for an exploratory run. The default is three
pairs. Each pair runs the peers sequentially; the peer that runs first
alternates. Every executable calibrates each corpus/operation to about 50 ms
and records 15 samples. ReleaseFast and the native CPU are the defaults.

Each benchmark creates an ignored directory under `benchmarks/` containing:

- immutable copies of both executables and every corpus;
- raw stdout and stderr from every timed run;
- exact output records captured before and after timing;
- `summary.json` with environment, hashes, binary sizes, and timings;
- `comparison.md`, the human-readable report.

Render a saved report again with:

```sh
make report SUMMARY=benchmarks/<run>/summary.json
```

The reported ratio is `uucode time / Zunic time`: above 1 means Zunic took
less time, below 1 means uucode took less time.

## Comparability limits

Both implementations receive the exact same valid UTF-8 bytes, and file I/O
is excluded from timing. The adapters consume equivalent results and the
driver compares their exact output records. It also verifies that each timed
count and checksum agrees with that peer's dump and that neither output nor
the source corpus changes during a run.

Zunic uses Unicode 16.0.0 while this pinned uucode revision uses Unicode
17.0.0. Their terminal-width policies also differ. Output differences are
therefore reported per corpus rather than treated as benchmark failures.
Measured traversal excludes Zunic's `renderable` result because uucode has no
counterpart. uucode is configured with only the four table fields its
grapheme and width APIs need; unused Unicode properties are not built into its
runtime tables.

Binary size is recorded but is not directly comparable as library size: each
standalone executable includes its adapter, timing harness, embedded corpora,
and whatever tables that peer's used operations require.
