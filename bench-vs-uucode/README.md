# uucode comparison benchmarks

Compare the current Zunic working tree with
[uucode 0.2.0](https://github.com/jacobsandlund/uucode) at pinned commit
`f67fa5dbef5c9de57773dbe2f7a02bebc7e20301`. Both peers are Zig libraries and
are built with the same Zig version, target, optimization mode, and CPU model.
The dependency hash in `build.zig.zon` verifies the fetched package.

uucode and Zunic overlap in eight bytes-to-results operations:

| Operation | Zunic | uucode | Timed result consumed |
|---|---|---|---|
| UTF-8 decoding | `zunic.utf8.step` | `uucode.utf8.Iterator` | code point and ending byte offset |
| Grapheme segmentation | `text(...).graphemes()` | `grapheme.utf8Iterator` | every start/end byte range |
| Measured graphemes | measured grapheme iterator | `grapheme.wcwidthNext` | every start/end range and cluster width |
| Whole-text width | `text(...).width()` | `grapheme.utf8Wcwidth` | total columns |
| Terminal properties | EAW, emoji predicates, and `widthProperties` | matching generated fields | every scalar's ending offset and property values |
| Full case folding | `fullCaseFold` | `case_folding_full` | every bounded mapping |
| Streaming graphemes | `graphemeBreak` | `computeGraphemeBreak` | every adjacent-pair boundary and ending offset |
| Ghostty scalar width | public width/GCB composition | matching uucode field composition | derived width for every scalar |

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
is excluded from timing. Scalar-property rows include UTF-8 decoding because
their public contracts start from bytes. The adapters consume equivalent
results and the driver compares their exact output records. It also verifies that each timed
count and checksum agrees with that peer's dump and that neither output nor
the source corpus changes during a run.

Both peers now use Unicode 17.0.0. Their whole-grapheme terminal-width policies
still differ, so output differences are reported per corpus rather than treated
as benchmark failures. Terminal-property, full-fold, and Ghostty-width outputs
must match exactly. Streaming boundaries match on the document corpora; the
focused corpus pins the known isolated-emoji-modifier difference between
Zunic's default UAX #29 GB9 behavior and uucode's modifier tailoring.
Measured traversal excludes Zunic's `renderable` result because uucode has no
counterpart. uucode is configured with only the table fields used by the eight
operations; unrelated Unicode properties are not built into its runtime tables.
The eight multilingual document corpora are supplemented by a small maintained
`features` corpus containing expanding/common folds, valid VS15/VS16 sequences,
an emoji modifier, a ZWJ sequence, a regional-indicator pair, combining marks,
prepend, and an Indic conjunct.

Binary size is recorded but is not directly comparable as library size: each
standalone executable includes its adapter, timing harness, embedded corpora,
and whatever tables that peer's used operations require.
