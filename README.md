# zunic

Allocation-free Unicode primitives for Zig terminal applications.

The package currently provides tolerant UTF-8 stepping, Unicode 16.0.0
extended-grapheme segmentation, default Unicode 16.0.0 UAX #14 line-break
boundaries, default Unicode 16.0.0 UAX #29 word boundaries, Unicode 16.0.0
UAX #15 canonical normalization, and a terminal cell-width policy. Its
grapheme, line-break, word and normalization implementations pass the official
Unicode 16.0.0 conformance fixtures.

Open the text view with `zunic.text(bytes)`. It borrows its bytes,
and its methods are the questions: `.graphemes()` partitions
user-visible text, `.width()` measures terminal columns, `.wrap(options)`
chooses display lines, `.terminators()` locates hard line breaks, and
`.wordBounds()` partitions the text into words and separators.
The view does not allocate. Opening it performs no scan;
work begins when a direct query such as `.width()` runs or an iterator is
consumed.

> **Strip ANSI escape sequences before using `zunic.text`.**
> It reads every byte as content, so an escape sequence is measured as the
> ordinary characters it is made of. `"\x1b[31mred\x1b[0m"` reports a width
> of 10 rather than 3, and wrapping it to 3 columns yields
> `"\x1b[31"`, `"mre"`, `"d\x1b[0"`, `"m"` -- breaks land inside the
> sequence and the output is corrupt. This is a deliberate boundary: `text`
> makes no attempt to recognise terminal control sequences. A `terminal` view
> that does may be added later.

## Why zunic

- **No allocator, anywhere.** No API takes an `std.mem.Allocator`, so
  nothing can fail on allocation. Iterators return borrowed byte offsets
  into the caller's input; state lives in the iterator struct.
- **No dependencies.** Zig standard library only. The Unicode tables are
  generated into the source tree, so there is no build-time download,
  code generation step, or C library to link.
- **Conformance-tested, not hand-tuned.** `zig build test` runs the
  official Unicode 16.0.0 `GraphemeBreakTest`, `LineBreakTest`,
  `WordBreakTest` and `NormalizationTest` fixtures, embedded in the
  repository, over every case they define.
- **Tolerant.** Malformed UTF-8 never errors and never
  panics. An invalid byte is consumed as one span with defined fallback
  properties, so a terminal reading arbitrary bytes keeps making
  progress.
- **Question-shaped API.** Typed byte, grapheme, and column coordinates keep
  coordinate systems distinct. Use `.measured()` only when a render loop
  needs a cluster's terminal width.
- **Optimized wrapping.** Grapheme segmentation, UAX #14 boundaries, and
  terminal widths are fused only where wrapping needs all three facts.
- **Checked ASCII fast path.** Runs of plain ASCII take a vectorized
  scan on aarch64 and x86_64. It is portable `@Vector` code with no
  intrinsics, checked against the scalar implementation for every byte
  value at every alignment. It needs no configuration, and the backend
  is selectable at build time.

## Usage

Add the dependency:

```sh
zig fetch --save git+https://github.com/vrypan/zunic.git#v0.3.0
```

Add the module in your application's `build.zig`:

```zig
const zunic = b.dependency("zunic", .{});
exe.root_module.addImport("zunic", zunic.module("zunic"));
```

No build flags are required. The vectorized ASCII fast path is enabled by
default wherever a backend exists, currently aarch64 and x86_64, and falls
back to the scalar path everywhere else. To pin a backend, pass the option
through the dependency rather than to your own build:

```zig
const zunic = b.dependency("zunic", .{ .@"wrap-fast-path" = .off });
```

Accepted values are `.auto` (the default), `.scalar`, `.simd`, and `.off`.
`-Dwrap-fast-path` applies when building zunic itself, such as running its
tests or benchmarks.

Then import `zunic` in application code. This example iterates measured
graphemes and reads their borrowed spans:

```zig
const std = @import("std");
const zunic = @import("zunic");

pub fn main() void {
    const text = "Hello, 👋 world";

    var graphemes = zunic.text(text).graphemes().measured().iterator();
    while (graphemes.next()) |span| {
        const cluster = text[span.start.value..span.end.value];
        std.debug.print("{s}: {} columns\n", .{
            cluster,
            span.columns,
        });
    }
}
```

## Wrapping terminal text

`zunic.text(bytes).wrap(options)` opens greedy display lines by terminal
columns. It preserves extended grapheme clusters and default UAX #14 break
opportunities. Hard line separators are consumed rather than included in the
returned span.

```zig
var lines = (try zunic.text(text).wrap(.{ .max_columns = 80 })).iterator();
while (lines.next()) |line| {
    const visible = text[line.start.value..line.end.value];
    std.debug.print("{s} ({d} columns)\n", .{ visible, line.columns.value });
}
```

The iterator prefers the last legal break that fits. The default `.grapheme`
overflow policy then breaks an unbreakable word before the grapheme that would
overflow; use `.overflow = .allow` to keep that run on one oversized line.
Zero-column suffixes remain attached to an oversized line, and a following
hard separator is consumed without producing a phantom line. Spans retain
whitespace, tabs, controls, and malformed bytes; apply the renderer's
filtering policy before writing terminal output.

## API reference

All text input is borrowed as `[]const u8`. Opening a view does not scan or
allocate; work happens when a method or iterator is consumed. Returned offsets
are relative to the exact slice passed to `text`.

### Text view

`text` is the top-level entry point for text operations:

```zig
pub fn text(bytes: []const u8) Text;

pub const Text = struct {
    bytes: []const u8,

    pub fn graphemes(self: Text) Graphemes;
    pub fn width(self: Text) usize;
    pub fn wrap(self: Text, options: WrapOptions) error{InvalidWidth}!Wrapped;
    pub fn terminators(self: Text) Terminators;
    pub fn wordBounds(self: Text) WordBounds;

    pub fn eql(self: Text, other: []const u8, comptime how: Equivalence)
        error{ InvalidUtf8, SequenceTooLong }!bool;
    pub fn isNormalized(self: Text, comptime form: Form)
        error{ InvalidUtf8, SequenceTooLong }!bool;
};
```

The view keeps the interpretation and the borrowed input together. Its
questions use specialized scans: asking for width does not materialize
grapheme spans, and finding terminators does not invoke the wrapping engine.
Only `wrap` returns an error, and only when `max_columns` is zero. Malformed
UTF-8 is handled by the tolerant recovery policy described below.

### Coordinates and returned values

Byte offsets and display columns are deliberately distinct return types. Each
coordinate has a public `value: usize` field.

| Type | Fields | Meaning |
| --- | --- | --- |
| `ByteOffset` | `value: usize` | Byte position relative to the input slice |
| `Column` | `value: usize` | Zero-based terminal display column |
| `Span` | `start: ByteOffset`, `end: ByteOffset` | Half-open borrowed byte range |
| `MeasuredSpan` | `start`, `end`, `columns: u2`, `renderable: bool` | Grapheme range plus terminal measurement |
| `Line` | `start: ByteOffset`, `end: ByteOffset`, `columns: Column` | One wrapped display line |

Use `bytes[span.start.value..span.end.value]` to recover the borrowed content.
For `MeasuredSpan`, ordinary renderable clusters have `renderable = true` and
one or two columns. A zero-column cluster has `columns = 0` and
`renderable = false`; a cluster outside the terminal policy is represented as
one column with `renderable = false`, so a caller can replace or omit it.

### Grapheme traversal

`zunic.text(bytes).graphemes()` applies the default Unicode 16.0.0
extended-grapheme rules. Its result deliberately has only two traversal paths:

| Traversal | Iterator item |
| --- | --- |
| `.iterator()` | `Span` with the grapheme's byte range |
| `.measured().iterator()` | `MeasuredSpan` with the range, terminal columns, and renderability |

Both are lazy, allocation-free forward scans. Count or select graphemes by
folding the iterator when needed:

```zig
var count: usize = 0;
var it = zunic.text(text).graphemes().iterator();
while (it.next() != null) count += 1;
```

### Width

`zunic.text(bytes).width()` returns the terminal-cell width of the complete
input. Width is computed by grapheme cluster, so emoji and regional-indicator
sequences are not counted scalar by scalar. Control characters and malformed
bytes have no display width under the package policy.

To compute the starting column of the grapheme containing a byte offset, scan
the measured graphemes. An offset at or past the end produces the total width:

```zig
var column: usize = 0;
var it = zunic.text(text).graphemes().measured().iterator();
while (it.next()) |span| {
    if (offset < span.end.value) break;
    column += span.columns;
}
```

### Wrapping

The wrapping options are:

```zig
pub const Overflow = enum { allow, grapheme };

pub const WrapOptions = struct {
    max_columns: usize,
    overflow: Overflow = .grapheme,
};
```

`zunic.text(bytes).wrap(options)` returns a `Wrapped` result. Its `.iterator()`
performs a lazy forward scan and returns `?Line`; `.count()` scans and counts
all returned lines. Each `Line` contains a borrowed half-open byte range and
its terminal-column count.

The algorithm greedily chooses the last legal Unicode line-break opportunity
that fits. With `.overflow = .grapheme`, an unbreakable run is split at a
grapheme boundary. With `.overflow = .allow`, it stays on an oversized line
until a legal opportunity is found. Hard terminator bytes are consumed and
excluded from returned lines. Other spaces and bytes are retained.

### Hard line terminators

`zunic.text(bytes).terminators()` locates the hard line breaks as byte
extents. Seven code points terminate a line -- `U+000A` LF, `U+000B` VT,
`U+000C` FF, `U+000D` CR, `U+0085` NEL, `U+2028` and `U+2029` -- and `\r\n`
is reported as a single terminator two bytes long.

The returned `Terminators` result provides `.iterator()`, whose `.next()`
returns `?Span`, and `.count()`, which scans the input. The iterator reports
only terminators physically present in the input; it does not emit an item at
end of text. A truncated UTF-8 sequence is not mistaken for a multibyte
terminator. This is a dedicated byte scan: it does not decode every scalar or
invoke grapheme, line-break, or wrapping machinery.

Paragraph content is the gaps between them:

```zig
var pos: usize = 0;
var it = zunic.text(text).terminators().iterator();
while (it.next()) |t| {
    consumeParagraph(text[pos..t.start.value]);
    pos = t.end.value;
}
if (pos < text.len) {
    consumeParagraph(text[pos..]);
}
```

This recipe treats terminators as endings: `"a\n"` has one paragraph and no
empty tail, while `"a\n\nb"` preserves the empty paragraph between the two
terminators. `"\n"` contains one empty paragraph. Adjust the final condition
if separator semantics are more appropriate for the application.

### Word boundaries

`zunic.text(bytes).wordBounds()` applies the default, locale-independent word
boundaries of [UAX #29 revision 45](https://www.unicode.org/reports/tr29/tr29-45.html#Word_Boundaries),
pinned to Unicode 16.0.0. The implementation passes every case of the official
`WordBreakTest-16.0.0.txt`, embedded in the repository.

```zig
pub const WordBounds = struct {
    bytes: []const u8,
    pub fn iterator(self: WordBounds) WordBoundIterator;
};

pub const WordBound = struct {
    start: ByteOffset,
    end: ByteOffset,
    is_word: bool,
};
```

The segments **partition** the input. Punctuation and whitespace are segments
too, flagged `is_word = false`, and adjacent non-word segments are not merged:
a comma and the space after it are two items. The first segment starts at
zero, each one starts where the previous ended, and the last ends at
`bytes.len`. Empty input yields nothing, and nothing is emitted for the start
or end of text.

```zig
var it = zunic.text(line).wordBounds().iterator();
while (it.next()) |segment| {
    if (segment.is_word) {
        consumeWord(line[segment.start.value..segment.end.value]);
    }
}
```

`"The price is $9.99 -unless you pay cash."` is 18 segments, 8 of them words.
WB11 and WB12 keep the decimal point inside `9.99`, while the period after
`cash` breaks off because no letter follows it, and `-` is `Word_Break=Other`
so it stands alone. Splitting on non-alphanumeric characters gets the decimal
wrong even though it gets the trailing period right.

**`is_word` is a zunic convenience, not a UAX #29 rule** and not a claim that
the segment is a linguistic word. It is true when at least one scalar in the
segment satisfies:

```text
Alphabetic = Yes  OR  General_Category in {Nd, Nl, No}
```

It cannot be read off `Word_Break`. `U+4E00` is `Word_Break=Other` and
Alphabetic; `U+00B2` SUPERSCRIPT TWO is `Word_Break=Other` with `GC=No`. The
predicate also covers some combining marks, so an isolated `U+0345` counts as
word-like while an isolated `U+0308` does not.

> **These are the *default* boundaries.** They do no dictionary lookup and no
> locale tailoring, so they do not find words in Thai, Lao, Khmer, Myanmar,
> Chinese or Japanese text: those need mechanisms this package does not
> provide. The limitation is broader than UAX #14's SA caveat.

Malformed input follows the package policy: each invalid byte is consumed on
its own as `Word_Break=Other`, neither pictographic nor word-like, and the
boundary rules then apply to it unchanged -- so a following `Extend` still
attaches to it by WB4. `"a\xffb"` is three segments, flagged word, non-word,
word. This behaviour is pinned by zunic's tests and is outside the Unicode
conformance claim.

Traversal is linear and the iterator holds constant memory, whatever the input
contains. WB6, WB7b and WB12 have to look past a punctuation candidate for the
next character WB4 does not fold away, and the run of folded characters between
them can be arbitrarily long; each such run is crossed at most once, so a
complete traversal decodes fewer than two scalars per input scalar.

### Canonical normalization

`zunic` implements **Unicode 16.0 Normalization Forms C and D** (UAX #15),
passing every case of the official `NormalizationTest-16.0.0.txt`.

**Only the canonical forms.** There is no NFKC or NFKD, and `Form` and
`Equivalence` have no values for them, so the compiler rejects the request
rather than answering it wrongly. This matters: `"\u{FB01}"` and `"fi"` are
*compatibility*-equivalent but **not** canonically equivalent, and a caller who
assumes otherwise gets silently wrong results in search and deduplication.

Two questions hang off the view, and both are allocation-free:

```zig
const same = try zunic.text("caf\u{00E9}").eql("cafe\u{0301}", .canonical); // true
const done = try zunic.text("caf\u{00E9}").isNormalized(.nfc);              // true
```

`eql` compares two NFD traversals in lockstep without materializing either
form, and takes no `Form`: canonical equivalence is form-independent, since
`NFD(a) == NFD(b)` exactly when `NFC(a) == NFC(b)`.

`isNormalized` resolves `NFC_QC`'s tri-valued `Maybe` internally rather than
leaking a third state into the API. A `Maybe` costs real work to settle, so
text full of composable marks is slower than text that is plainly already
normalized.

Producing normalized bytes is a top-level iterator, because it makes new
scalars rather than spans into the caller's input:

```zig
pub const Form = enum { nfc, nfd };
pub const Equivalence = enum { canonical };

pub fn normalize(bytes: []const u8, comptime form: Form) NormalizationIterator(form);
pub fn normalizedLenBound(input_len: usize, comptime form: Form) error{Overflow}!usize;

// On the iterator:
pub fn next(self: *Self) error{ InvalidUtf8, SequenceTooLong }!?u21;
pub fn writeTo(self: Self, buffer: []u8)
    error{ NoSpace, InvalidUtf8, SequenceTooLong }![]u8;
```

```zig
const capacity = try zunic.normalizedLenBound(input.len, .nfc);
// caller supplies a buffer of at least `capacity` bytes
const output = try zunic.normalize(input, .nfc).writeTo(buffer);
```

`normalizedLenBound` is checked `len * 3`, and three is achieved, not padded:
`U+0390` decomposes from two bytes to six, a Hangul LVT syllable from three to
nine, and NFC reaches it too: `U+1D160` decomposes into three supplementary
musical symbols (`U+1D158 U+1D165 U+1D16E`), growing from four bytes to twelve.
Composition exclusions prevent these symbols from recomposing. The generator
verifies that eligible compositions do not increase UTF-8 byte length, so the
NFD bound also bounds NFC.

Sufficient capacity rules out `NoSpace` and nothing else. `writeTo` takes the
iterator by value, so a temporary chains and a stored one is left where it was,
resuming from its own position rather than the start of the input.

#### The combining-sequence limit

The working buffer is inline and fixed at compile time, so a combining sequence
longer than it holds is **rejected with `error.SequenceTooLong`** -- never
truncated, never silently reordered, and never quietly declared equal to
something else. The default 128 bytes admits a run of **30 non-starters**,
counted after full canonical decomposition:

```zig
const zunic = b.dependency("zunic", .{ .@"normalization-buffer-bytes" = @as(usize, 256) });
```

The value must be a positive multiple of 32; 32, 64, 128 and 256 bytes give
limits of 6, 14, 30 and 62. This is zunic's resource limit, not the Stream-Safe
Text Format of UAX #15 section 13, which counts after NFKD; valid Unicode
permits arbitrarily long combining sequences. It does not restrict the grapheme
iterator, which has no such limit.

#### Errors

Normalization is the one part of zunic that is **strict about malformed
UTF-8**. An invalid encoding is `error.InvalidUtf8`: never a replacement
character, never a skipped byte, so two different invalid inputs cannot compare
equal by both decaying to `U+FFFD`. A validly encoded `U+FFFD` is ordinary
input. Grapheme, word, width, wrapping and `utf8.step` keep their tolerant
recovery.

The four errors mean different things, and only one of them is worth retrying:

| error | cause | fix |
| --- | --- | --- |
| `NoSpace` | destination too small | retry with `normalizedLenBound` bytes |
| `Overflow` | `len * 3` exceeds `usize` | nothing; the input cannot be sized |
| `SequenceTooLong` | run past the configured limit | raise `normalization-buffer-bytes`, or reject the input |
| `InvalidUtf8` | the bytes are not UTF-8 | fix the input |

On any error the destination holds a partial result, and the bytes after the
written prefix are unchanged. An iterator that has failed stays failed and
returns the same error forever. Normalization runs one combining run ahead of
its output -- a starter cannot be emitted until you know whether a following
mark reorders before it or composes into it -- so a failure can preempt the run
still being accumulated: `"ab\xff"` reports `InvalidUtf8` having yielded only
`a`. Everything actually returned is correct.

Both queries short-circuit. A decisive `false` may leave the rest of the input
unread, so neither is a whole-input validator; a `true` answer does mean the
whole input was examined and accepted. Once either query encounters
`InvalidUtf8` or `SequenceTooLong`, the error wins over any boolean it might
otherwise have returned at that point.

### Unicode line-break boundaries

`zunic.line_break` is the low-level default, locale-independent Unicode 16.0
UAX #14 revision 53 boundary API:

```zig
pub const Opportunity = enum {
    prohibited,
    allowed,
    mandatory,
};

pub const Boundary = struct {
    offset: usize,
    opportunity: Opportunity,
};

pub fn iterator(bytes: []const u8) Iterator;
```

Unlike APIs that yield only usable breaks, this iterator returns every scalar
boundary, including prohibited ones. Non-empty input begins with a prohibited
boundary at offset zero and ends with a mandatory boundary at `bytes.len`;
empty input produces one mandatory boundary at zero.

```zig
var boundaries = zunic.line_break.iterator(text);
while (boundaries.next()) |boundary| {
    switch (boundary.opportunity) {
        .prohibited => {},
        .allowed => std.debug.print("may break at {d}\n", .{boundary.offset}),
        .mandatory => std.debug.print("must break at {d}\n", .{boundary.offset}),
    }
}
```

This API reports boundary opportunities. It does not fit text to terminal
columns, tailor rules by locale, or perform dictionary segmentation for
complex South East Asian text. Use `text(bytes).wrap(options)` when the desired
result is a sequence of display lines.

### Tolerant UTF-8 stepping

`zunic.utf8.step` is the lowest-level public operation:

```zig
pub const Step = struct {
    len: usize,
    cp: ?u21,
};

pub fn step(bytes: []const u8) Step;
```

For a valid leading scalar, `len` is its encoded byte length and `cp` contains
the code point. For non-empty malformed input, `len` is one and `cp` is null,
so callers always make progress. Empty input returns `.len = 0` and
`.cp = null`.

```zig
var offset: usize = 0;
while (offset < bytes.len) {
    const decoded = zunic.utf8.step(bytes[offset..]);
    if (decoded.cp) |cp| {
        std.debug.print("U+{X}\n", .{cp});
    } else {
        std.debug.print("invalid byte at {d}\n", .{offset});
    }
    offset += decoded.len;
}
```

Higher-level APIs use the same recovery rule. Each invalid byte acts as one
advancing, AL-like fallback scalar for line breaking and contributes no
terminal columns.

### Diagnostic exports

`zunic.build_options.wrap_fast_path` reports the configured fast-path option.
`zunic.testing.instrumentedIterator` exposes wrapping work counters for this
package's tests. Application code should normally use
`zunic.text(bytes).wrap(options)`.

## Development

Run `make benchmark` to measure ReleaseFast throughput for UTF-8, grapheme,
measured-grapheme, width, line-break, terminator, word-boundary, and wrapping
workloads. It reports seven samples per case; compare results on the same
machine rather than treating them as cross-machine rankings. Use
`make benchmark` with `BENCHMARK_ARGS=--smoke` for a quicker smoke run.

```sh
zig build test
```

The Unicode tables are generated into the source tree and committed, so
building needs no Python. Regenerating them does:

```sh
python3 src/tools/generate-properties.py                # src/properties.zig
python3 src/tools/generate-word-properties.py           # src/word_properties.zig
python3 src/tools/generate-normalization-properties.py  # src/normalization_properties.zig
python3 src/tools/test-properties.py                    # verify, all 1,114,112 points
python3 src/tools/test-word-properties.py               # verify, all 1,114,112 points
python3 src/tools/test-normalization-properties.py      # verify, all 1,114,112 points
```

Each checker re-derives every fact from the pinned UCD files and decodes the
emitted Zig, sharing no classification code with its generator, so a mismatch
means the generator is wrong rather than the output.
