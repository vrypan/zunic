# uucode comparison benchmarks

Compare the current Zunic working tree with
[uucode 0.2.0](https://github.com/jacobsandlund/uucode) at pinned commit
`cba2b5bc9f79d200541a7f4fdd62a1ba5ca5f166` (Zig 0.17 compatibility). Both peers are Zig libraries and
are built with the same Zig version, target, optimization mode, and CPU model.
The dependency hash in `build.zig.zon` verifies the fetched package.

> [!NOTE]
> These benchmarks do not measure which library is better, or even which one
> is faster in general. They provide measurements from a specific setup that
> gives me a baseline for comparison.
>
> That said, I believe they show that in many cases, Zunic is comparable to
> uucode in performance.

## Latest results

These results cover **Zunic v0.6.0**. The measurements preceded the release
metadata bump; the runtime library code is unchanged. Exact measured commits
and archive provenance are recorded in [TIMINGS.md](TIMINGS.md).

Recorded on 2026-10-05 on an Apple M4 ARM64 machine running macOS 27.0.1.
Both peers used Unicode 17.0.0, Zig 0.17.0, ReleaseFast, and the native CPU
target. uucode was pinned to
`cba2b5bc9f79d200541a7f4fdd62a1ba5ca5f166`. The run included all eighteen
operations and nine corpora, with three alternating pairs and 15 samples per
executable run. See [TIMINGS.md](TIMINGS.md) for every per-corpus measurement.

The UTF-8 row was rerun separately after changing its adapter to the public
`text(bytes).codepoints().iterator()`. This rerun used the same v0.6.0 runtime
library code, settings, peer revision, corpora, three-pair protocol, and sample
count. The other seventeen rows retain the full-run measurements. Both archives record source and binary
hashes; the focused archive identifies the uncommitted adapter change.

Both peer-adapter tests and the CLI, exact-dump, filtered-operation, and
operation-contract checks passed. Timed counts and checksums matched each
peer's dumps, and exact outputs and corpus hashes remained unchanged throughout
the run. Known grapheme and width-policy differences are reported below.

For each corpus, the result is the median of the three run medians. The average
below is the geometric mean of the nine per-corpus ratios. `uucode/Zunic` above
1 means Zunic took less time. The range shows the lowest and highest corpus
ratio; it is useful where different input classes exercise different fast
paths.

| Benchmark class | Geometric mean uucode/Zunic | Range | Exact outputs |
|---|---:|---:|---:|
| UTF-8 decoding | 1.67× | 1.29–2.16× | 9/9 |
| Extended grapheme ranges | 1.49× | 1.22–1.83× | 8/9 |
| Grapheme ranges with cluster width | 1.63× | 1.43–1.94× | 7/9 |
| Whole-text grapheme width | 3.75× | 1.45–97.90× | 7/9 |
| Unicode terminal property facts | 1.46× | 1.36–1.54× | 9/9 |
| Fused scalar terminal-property lookup | 1.37× | 1.34–1.42× | 9/9 |
| Full default case folding | 1.29× | 1.17–1.43× | 9/9 |
| Simple uppercase mapping | 1.24× | 1.02–1.53× | 9/9 |
| Simple lowercase mapping | 1.19× | 1.06–1.48× | 9/9 |
| Simple titlecase mapping | 1.23× | 1.02–1.48× | 9/9 |
| Exact numeric properties | 2.09× | 2.01–2.27× | 9/9 |
| Primary Script property | 1.02× | 0.98–1.11× | 9/9 |
| Bidirectional scalar properties | 1.37× | 1.28–1.48× | 9/9 |
| Bidirectional scalar mappings | 1.22× | 1.15–1.36× | 9/9 |
| Canonical combining class | 1.03× | 0.93–1.24× | 9/9 |
| Immediate decomposition facts | 1.18× | 1.00–1.34× | 9/9 |
| Incremental grapheme boundaries | 2.74× | 1.92–3.70× | 8/9 |
| Ghostty scalar-width composition | 1.28× | 1.13–1.54× | 9/9 |

Full-run archive: `benchmarks/20261005T113605Z-zig017-5f95f7c-ae1079/summary.json`.
UTF-8 iterator rerun: `benchmarks/20261005T134156Z-zig017-public-codepoints-8be596/summary.json`.
Both directories contain raw samples, before/after dumps, executable copies,
and corpus snapshots with recorded hashes.

[Results breakdown: full per-corpus timings](TIMINGS.md)

uucode and Zunic overlap in eighteen benchmarked operations:

| Operation | Zunic | uucode | Timed result consumed |
|---|---|---|---|
| UTF-8 decoding | `text(...).codepoints().iterator()` | `uucode.utf8.Iterator` | code point and ending byte offset |
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
| Primary Script | `cp(value).script()` | configured `script` field | every predecoded scalar and Script enum value |
| Bidi properties | `cp(value).bidi()` | configured class, mirrored, and paired-bracket fields | every predecoded scalar's normalized class, mirrored flag, and bracket type |
| Bidi mappings | the two optional mapping methods | mirroring and paired-bracket fields | presence and target of every optional mapping |
| Combining class | `cp(value).canonicalCombiningClass()` | `canonical_combining_class` | every predecoded scalar and class |
| Decomposition | `cp(value).decomposition()` | decomposition type and mapping | every immediate mapping and type |
| Streaming graphemes | `graphemeBreak` | `computeGraphemeBreak` | every adjacent-pair boundary and ending offset |
| Ghostty scalar width | public width/GCB composition | matching uucode field composition | derived width for every scalar |

The UTF-8 row measures public scalar iteration: Zunic's
`text(bytes).codepoints().iterator()` returns `CodepointView`, while uucode's
`utf8.Iterator` returns scalar values. Both adapters consume the scalar value
and ending byte offset. Zunic's property lookups remain lazy and are not
requested in this row. All inputs are valid UTF-8; this does not benchmark
malformed-input or error-handling behavior.

Property rows use the current `cp(value)` API; grapheme rows use the tolerant
text iterators. Simple case mapping, numeric properties, Script, bidi
properties and mappings, combining class, and decomposition receive
predecoded codepoints so their timings isolate lookup and result handling.

uucode does not currently expose comparable line breaking, complete text
normalization, Script_Extensions, word boundaries, or wrapping, so those Zunic
features are not included. The shared corpora are the same eight multilingual
files used by `bench-vs-rust`; the suite checks them before use and embeds them
into both executables.

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
numeric_properties, script, bidi_properties, bidi_mappings, combining_class, decomposition,
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

Both peers now use Unicode 17.0.0. Their primary Script enum ordinals agree,
and the benchmark checks every emitted Script result exactly. Their
whole-grapheme terminal-width policies still differ, so output differences are
reported per corpus rather than treated as benchmark failures.
Terminal-property, case-mapping, numeric, Script, normalization-fact,
full-fold, and Ghostty-width outputs must match exactly.
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
