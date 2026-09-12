# uucode comparison benchmarks

Compare the current Zunic working tree with
[uucode 0.2.0](https://github.com/jacobsandlund/uucode) at pinned commit
`f67fa5dbef5c9de57773dbe2f7a02bebc7e20301`. Both peers are Zig libraries and
are built with the same Zig version, target, optimization mode, and CPU model.
The dependency hash in `build.zig.zon` verifies the fetched package.

> [!NOTE]
> These benchmarks do not measure which library is better, not even
> which one is faster. Thes provide measurements taken in a very specific
> setup, that that give me a baseline I can compare agains.
>
> That said, I believe they show that in many cases, zunic is comparable to uucode
> in performance.

## Latest results

Recorded on 2026-09-12 at Zunic `d82ae3d` on an Apple ARM64 machine running
macOS 26.6.2. Both peers used Unicode 17.0.0, Zig 0.16.0, ReleaseFast, and the
native CPU target. The run used three alternating pairs and 15 samples per
executable run. See [TIMINGS.md](TIMINGS.md) for every per-corpus measurement.

For each corpus, the result is the median of the three run medians. The average
below is the geometric mean of the nine per-corpus ratios. `uucode/Zunic` above
1 means Zunic took less time. The range shows the lowest and highest corpus
ratio; it is useful where different input classes exercise different fast
paths.

| Benchmark class | Geometric mean uucode/Zunic | Range | Exact outputs |
|---|---:|---:|---:|
| UTF-8 decoding | 1.82× | 1.48–2.38× | 9/9 |
| Extended grapheme ranges | 2.21× | 1.65–2.82× | 8/9 |
| Grapheme ranges with cluster width | 2.68× | 2.26–3.69× | 7/9 |
| Whole-text grapheme width | 6.29× | 2.59–112.87× | 7/9 |
| Unicode terminal property facts | 1.91× | 1.52–2.13× | 9/9 |
| Fused scalar terminal-property lookup | 1.24× | 1.20–1.33× | 9/9 |
| Full default case folding | 1.09× | 0.97–1.37× | 9/9 |
| Simple uppercase mapping | 1.20× | 1.00–1.33× | 9/9 |
| Simple lowercase mapping | 1.16× | 1.02–1.33× | 9/9 |
| Simple titlecase mapping | 1.20× | 1.01–1.34× | 9/9 |
| Exact numeric properties | 2.26× | 2.12–2.85× | 9/9 |
| Canonical combining class | 1.05× | 0.95–1.26× | 9/9 |
| Immediate decomposition facts | 1.20× | 1.02–1.84× | 9/9 |
| Incremental grapheme boundaries | 2.64× | 1.94–3.93× | 8/9 |
| Ghostty scalar-width composition | 1.63× | 1.46–1.82× | 9/9 |

[Results breakdown: full per-corpus timings](TIMINGS.md)

uucode and Zunic overlap in fifteen benchmarked operations:

| Operation | Zunic | uucode | Timed result consumed |
|---|---|---|---|
| UTF-8 decoding | `zunic.utf8.step` | `uucode.utf8.Iterator` | code point and ending byte offset |
| Grapheme segmentation | `text(...).graphemes()` | `grapheme.utf8Iterator` | every start/end byte range |
| Measured graphemes | measured grapheme iterator | `grapheme.wcwidthNext` | every start/end range and cluster width |
| Whole-text width | `text(...).width()` | `grapheme.utf8Wcwidth` | total columns |
| Terminal properties | `cp(value).terminal()` | configured-table `getAll` | every scalar's ending offset and property values, including `Emoji` and `Emoji_Component` |
| Fused scalar terminal lookup | `cp(value).terminal()` | configured-table `getAll` | every predecoded scalar and property value, including `Emoji` and `Emoji_Component` |
| Full case folding | `cp(value).fullCaseFold()` | `case_folding_full` | every bounded mapping |
| Simple uppercase | `cp(value).simpleUppercase()` | `simple_uppercase_mapping` | every predecoded scalar and mapped value |
| Simple lowercase | `cp(value).simpleLowercase()` | `simple_lowercase_mapping` | every predecoded scalar and mapped value |
| Simple titlecase | `cp(value).simpleTitlecase()` | `simple_titlecase_mapping` | every predecoded scalar and mapped value |
| Numeric properties | `cp(value).numeric()` | numeric type and value fields | every exact reduced rational value and kind |
| Combining class | `cp(value).canonicalCombiningClass()` | `canonical_combining_class` | every predecoded scalar and class |
| Decomposition | `cp(value).decomposition()` | decomposition type and mapping | every immediate mapping and type |
| Streaming graphemes | `graphemeBreak` | `computeGraphemeBreak` | every adjacent-pair boundary and ending offset |
| Ghostty scalar width | public width/GCB composition | matching uucode field composition | derived width for every scalar |

The UTF-8 row measures the low-level `zunic.utf8.step()` decoder, not
`text(bytes).codepoints().iterator()`. It does not measure the public iterator's
`CodepointView` return or sticky `err` handling. Property rows use the current
`cp(value)` API; grapheme rows use the tolerant text iterators. Simple case
mapping, numeric properties, combining class, and decomposition receive
predecoded codepoints so their timings isolate lookup and result handling.

uucode does not currently expose comparable line breaking, complete text
normalization, word boundaries, or wrapping, so those Zunic features are not
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

Run a single operation or a comma-separated selection from the repository root:

```sh
make -C bench-vs-uucode bench OPERATIONS=combining_class
make -C bench-vs-uucode bench OPERATIONS=combining_class,decomposition PAIRS=1
```

`OPERATIONS=all` is the default. Every operation can be selected:

```text
utf8, graphemes, measured, width,
terminal_properties, terminal_lookup, case_fold,
simple_uppercase, simple_lowercase, simple_titlecase,
numeric_properties, combining_class, decomposition,
grapheme_stream, ghostty_width
```

Use comma-separated names without spaces. Unknown names, empty selections,
and duplicate names are rejected. Selected operations run across all corpora;
only those operations are timed, validated, and included in the saved report.
Both executables still include all operations, so filtering does not specialize
the build or change what the recorded binary size represents.

The Python driver accepts `--operations combining_class,decomposition`.
The executables accept the same option after `--bench` or `--dump`, for example
`./zig-out/bin/zunic-bench --bench --operations combining_class`.

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

## Ghostty coverage binary size

Build three stripped ReleaseFast binaries that exercise the Unicode operations
Ghostty obtains from uucode:

```sh
make ghostty-size
```

Ghostty configures uucode with generated properties. These are its direct
uucode calls and the calls made by its bundled libvaxis dependency, with the
corresponding public Zunic operations:

| uucode operation | Zunic operation |
|---|---|
| `uucode.config.max_code_point` | `zunic.max_codepoint` |
| `uucode.ascii.isAlphabetic(value)` | range-check and cast `value`, then use `std.ascii.isAlphabetic` |
| `uucode.ascii.toLower(value)` | range-check and cast `value`, then use `std.ascii.toLower` |
| `uucode.get(.case_folding_full, value).with(...)` | `zunic.cp(value).fullCaseFold().slice()` |
| `uucode.get(.is_emoji_presentation, value)` | `zunic.cp(value).terminal().isEmojiPresentation` |
| `uucode.get(.width, value)` | Ghostty's scalar-width composition from `zunic.cp(value).terminal()` and `.grapheme()` |
| `uucode.get(.wcwidth_zero_in_grapheme, value)` | `zunic.cp(value).terminal().zeroInGrapheme` |
| `uucode.get(.is_emoji_vs_base, value)` | `zunic.cp(value).terminal().isEmojiVariationBase` |
| `uucode.get(.is_symbol, value)` | `zunic.cp(value).general().category == .co` plus Ghostty's eight Unicode-block ranges |
| `uucode.get(.grapheme_break_no_control, value)` and `uucode.grapheme.computeGraphemeBreakNoControl(...)` | `zunic.graphemeBreak(...)`; the caller retains Ghostty's control filtering and emoji-modifier tailoring |
| `uucode.grapheme.isBreak(previous, current, state)` | `zunic.graphemeBreak(previous, current, state)` |
| `uucode.get(.general_category, value)` | `zunic.cp(value).general().category` |
| `uucode.get(.east_asian_width, value)` | `zunic.cp(value).terminal().eastAsianWidth` |
| `uucode.get(.grapheme_break, value)` | `zunic.cp(value).grapheme()` for raw classification |
| `uucode.utf8.Iterator.init(bytes)` | `zunic.text(bytes).codepoints().iterator()` |
| `uucode.grapheme.Iterator(uucode.utf8.Iterator).init(...)` | `zunic.text(bytes).graphemes().iterator()` |

The generated uucode `width` field combines standalone width,
zero-in-grapheme, emoji-modifier, and no-control grapheme facts. Zunic exposes
those facts through `cp(value).terminal()` and `cp(value).grapheme()`, allowing
Ghostty to retain its own scalar-width policy.

`ghostty-size-zunic` and `ghostty-size-uucode` consume equivalent runtime
results for general category, East Asian width, emoji presentation and
variation facts, terminal width facts, full case folding, grapheme facts, and
stateful grapheme breaking. `ghostty-size-control` has the same volatile input
and checksum shape without either library, so subtracting it approximates the
incremental linked cost. The uucode executable uses a separate dependency
instance containing only Ghostty's configured fields; benchmark-only numeric,
decomposition, and simple-case fields are absent.

This is an API-coverage size probe, not Ghostty's application binary. Ghostty
generates some facts at build time and applies application-owned width and
symbol policies; the probe retains all comparable capabilities to answer the
dependency-choice question consistently.

## Comparability limits

Both implementations receive the exact same valid UTF-8 bytes, and file I/O
is excluded from timing. The terminal-properties row includes UTF-8 decoding
because its public contract starts from bytes. The fused scalar lookup receives
predecoded code points and isolates the two table APIs. The new codepoint rows
also receive predecoded values. The adapters consume
equivalent results and the driver compares their exact output records. Multi-result
operations use independent field accumulators that are combined once after
traversal, reducing checksum dependency-chain overhead. The driver also verifies
that each timed count and checksum agrees with that peer's dump and that neither
output nor the source corpus changes during a run.

For numeric properties, Zunic returns a reduced rational directly. uucode
returns non-decimal numeric values as strings, so its timed adapter parses and
reduces those strings to produce the same result a caller receives from Zunic.

Both peers now use Unicode 17.0.0. Their whole-grapheme terminal-width policies
still differ, so output differences are reported per corpus rather than treated
as benchmark failures. Terminal-property, case-mapping, numeric,
normalization-fact, full-fold, and Ghostty-width outputs must match exactly.
Streaming boundaries match on the document corpora; the
focused corpus pins the known isolated-emoji-modifier difference between
Zunic's default UAX #29 GB9 behavior and uucode's modifier tailoring.
Measured traversal excludes Zunic's `renderable` result because uucode has no
counterpart. uucode is configured with only the table fields used by the
benchmarked operations; unrelated Unicode properties are not built into its
runtime tables.
Its `getAll("0", cp)` call returns every field assigned to generated table
`"0"`; this suite uses that low-level fused lookup for the terminal-property
row. The table name and returned fields depend on the consuming build's uucode
configuration rather than forming a fixed terminal-property API.
The eight multilingual document corpora are supplemented by a small maintained
`features` corpus containing expanding/common folds, simple case mappings,
numeric values, canonical and compatibility decompositions, valid VS15/VS16
sequences, an emoji modifier, a ZWJ sequence, a regional-indicator pair,
combining marks, prepend, and an Indic conjunct.

Binary size is recorded but is not directly comparable as library size: each
standalone executable includes its adapter, timing harness, embedded corpora,
and whatever tables that peer's used operations require.
