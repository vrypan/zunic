# Zunic documentation

Zunic provides allocation-free Unicode operations over borrowed bytes.
[`zunic.text(bytes)`](text/README.md) opens the main view for graphemes, width,
wrapping, trimming, terminators, words, normalization, validation, and ASCII
checks. `Text` exposes its borrowed input as `.bytes`; see
[shared conventions](conventions.md) for lifetimes and offsets.

## API overview

The signatures use names exported by `zunic`, grouped by API area.
They are an overview, not a standalone Zig file. `form` and `how` are compile-time
arguments. Unicode data is pinned to **17.0.0**.

```zig
pub const unicode_version: std.SemanticVersion; // 17.0.0
pub fn text(bytes: []const u8) Text;
```

### Text

```zig
// Text methods
pub fn validate(self: Text) error{InvalidUtf8}!void;
pub fn graphemes(self: Text) Graphemes;
pub fn codepoints(self: Text) Codepoints;
pub fn width(self: Text) usize;
pub fn wrap(self: Text, options: WrapOptions) error{InvalidWidth}!Wrapped;
pub fn trim(self: Text) Text;
pub fn trimStart(self: Text) Text;
pub fn trimEnd(self: Text) Text;
pub fn isWhitespace(self: Text, span: anytype) bool;
pub fn isAscii(self: Text) bool;
pub fn terminators(self: Text) Terminators;
pub fn wordBounds(self: Text) WordBounds;
pub fn normalize(self: Text, comptime form: Form) NormalizationIterator(form);
pub fn normalizedLenBound(self: Text, comptime form: Form) error{Overflow}!usize;
pub fn eql(self: Text, other: []const u8, comptime how: Equivalence) NormalizationError!bool;
pub fn isNormalized(self: Text, comptime form: Form) NormalizationError!bool;
pub fn isNormalizedQuick(self: Text, comptime form: Form) error{InvalidUtf8}!QuickCheck;
```

Opening a Text view does not scan. `validate()` checks the complete slice.
Grapheme, word, width, wrap, and trim operations tolerate malformed UTF-8;
codepoint iteration stops at it, and normalization rejects it when encountered.
Trimming returns another borrowed Text, with offsets relative to its retained slice.

#### Text iterators

Call `.iterator()` on a view, then `.next()` until it returns `null`.
Grapheme and wrapped iterator types are inferred; their internal names are not
exported. `Self` below means the corresponding iterator.

| View | Methods | Iterator result |
| --- | --- | --- |
| `Graphemes` | `.iterator()`, `.measured() → MeasuredGraphemes` | `next(self: *Self) ?Span` |
| `MeasuredGraphemes` | `.iterator()` | `next(self: *Self) ?MeasuredSpan` |
| `Codepoints` | `.iterator() → CodepointIterator` | `next(self: *Self) ?Codepoint` |
| `Wrapped` | `.iterator()`, `.count() → usize` | `next(self: *Self) ?Line` |
| `Terminators` | `.iterator() → TerminatorIterator`, `.count() → usize` | `next(self: *Self) ?Span` |
| `WordBounds` | `.iterator() → WordBoundIterator` | `next(self: *Self) ?WordBound` |

Normalization returns an iterator directly:

```zig
// NormalizationIterator(form)
pub fn next(self: *Self) NormalizationError!?u21;
pub fn writeTo(self: Self, buffer: []u8) NormalizationWriteError![]u8;
```

`writeTo()` writes the remaining normalized text as UTF-8 and returns the
written buffer slice. It takes a copy of the iterator. Use
`normalizedLenBound()` to size the output buffer; that bound does not increase
the separate combining-run limit.

#### Text options and results

```zig
pub const Form = enum { nfc, nfd, nfkc, nfkd };
pub const Equivalence = enum { canonical, compatibility };
pub const QuickCheck = enum { yes, no, maybe };
pub const NormalizationError = error{ InvalidUtf8, SequenceTooLong };
pub const NormalizationWriteError = NormalizationError || error{NoSpace};

// Iterator type constructor; use Text.normalize() to create an iterator.
pub fn NormalizationIterator(comptime form: Form) type;

pub const Overflow = enum { allow, grapheme };
pub const WrapOptions = struct {
    max_columns: usize,
    overflow: Overflow = .grapheme,
};
pub const MeasuredSpan = struct {
    start: ByteOffset,
    end: ByteOffset,
    columns: u2,
    renderable: bool,
};
pub const Line = struct { start: ByteOffset, end: ByteOffset, columns: Column };
pub const WordBound = struct { start: ByteOffset, end: ByteOffset, is_word: bool };
pub const Codepoint = CodepointView;
pub const DecodeError = enum { invalid_utf8 };
pub const CodepointIterator = struct {
    bytes: []const u8,
    offset: usize = 0,
    err: ?DecodeError = null,
    pub fn next(self: *CodepointIterator) ?CodepointView;
};
```

Columns follow Zunic's cell width policy. `.grapheme` allows wrapping
inside an otherwise unbreakable word; `.allow` lets it exceed the limit.
Neither splits an individual grapheme. A zero width is `InvalidWidth`.
`isWhitespace(span)` accepts a `Span` or `MeasuredSpan` from the same Text slice.
`isAscii()` scans the whole slice on every call, with no cache; it is a
byte-range test, not UTF-8 validation.

`codepoints()` yields the same `CodepointView` as `zunic.cp(value)`;
`Codepoint` is an alias for that type. Its `value` is a nonoptional `u21`,
and `general()`, `terminal()`, `grapheme()`, and other scalar methods are
available directly. Iteration decodes only; property lookups happen when asked.

The iterator stops at the first malformed UTF-8 sequence. After `next()`
returns `null`, `err == null` means normal exhaustion; `.invalid_utf8` means
failure. The byte `offset` points to the next scalar, stays at the start of
an undecodable sequence on failure, and equals the input length after normal
exhaustion. Repeated calls after either outcome return `null` and preserve
`err` and `offset`. If you stop the loop early, `err == null` only describes
the prefix already visited. Copying the iterator creates an independent
checkpoint over the same borrowed bytes.

```zig
var it = zunic.text(bytes).codepoints().iterator();
while (it.next()) |point| {
    const p = point.general();
    std.debug.print("{x}: {s}\n", .{ point.value, @tagName(p.category) });
}
if (it.err) |err| {
    std.debug.print("{s} at byte {d}\n", .{ @tagName(err), it.offset });
}
```

Every yielded value is a valid Unicode scalar, including a literal U+FFFD.
There is no replacement sentinel. The old item fields `start`, `end`,
`width`, `grapheme`, and `east_asian_wide` are replaced by the iterator's
`offset` and the code-point methods. To retain a scalar's byte range, capture
`offset` before calling `next()` and after it returns an item.

`isNormalizedQuick()` scans the whole input and can return `.maybe` for a
composing form (`.nfc`/`.nfkc`); a decomposing form (`.nfd`/`.nfkd`) never
does. `isNormalized()` resolves the answer to a boolean and may stop early.
`.nfkc`/`.nfkd` also decompose compatibility mappings (ligatures, fullwidth
forms, and similar) that `.nfc`/`.nfd` leave untouched; `eql(..., .compatibility)`
is the matching broader equivalence. Full default case folding is available
through `cp(value).fullCaseFold()` as a separate scalar operation; it is not folded into
normalization or equality. Stream-safe normalization is not available.

### Shared positions and helpers

```zig
pub const ByteOffset = struct { value: usize };
pub const Column = struct { value: usize };
pub const Span = struct { start: ByteOffset, end: ByteOffset };

// Helpers for byte slices; scalar operations live on CodepointView.
pub fn isWhitespaceSlice(glyph: []const u8) bool;
pub fn isAscii(bytes: []const u8) bool;

pub fn cp(value: u21) CodepointView;
pub const CodepointView = packed struct(u32) {
    value: u21,
    _padding: u11 = 0,
    pub fn general(self: CodepointView) GeneralProperties;
    pub fn terminal(self: CodepointView) TerminalProperties;
    pub fn grapheme(self: CodepointView) GraphemeProperties;
    pub fn width(self: CodepointView) u2;
    pub fn isEastAsianWide(self: CodepointView) bool;
    pub fn isWhitespace(self: CodepointView) bool;
    pub fn fullCaseFold(self: CodepointView) CaseFold;
};

pub const max_codepoint: u21 = 0x10FFFF;
pub const GeneralCategory = enum(u5) { lu, ll, lt, lm, lo, mn, mc, me, nd, nl, no_, pc, pd, ps, pe, pi, pf, po, sm, sc, sk, so, zs, zl, zp, cc, cf, cs, co, cn };
pub const EastAsianWidth = enum(u3) { neutral, fullwidth, halfwidth, wide, narrow, ambiguous };
pub const GraphemeClass = enum(u4) { other, cr, lf, control, extend, zwj, regional_indicator, prepend, spacingmark, l, v, t, lv, lvt };
pub const IndicConjunctBreak = enum(u2) { none, consonant, extend, linker };

pub const GeneralProperties = packed struct(u32) {
    category: GeneralCategory,
    isAlphabetic: bool,
    isLowercase: bool,
    isUppercase: bool,
    isCased: bool,
    isCaseIgnorable: bool,
    isMath: bool,
    isIdStart: bool,
    isIdContinue: bool,
    isXidStart: bool,
    isXidContinue: bool,
    isDefaultIgnorable: bool,
    isGraphemeBase: bool,
    isGraphemeExtend: bool,
    _padding: u14 = 0,
};

pub const TerminalProperties = packed struct(u10) {
    eastAsianWidth: EastAsianWidth,
    isEmojiPresentation: bool,
    isEmojiVariationBase: bool,
    isEmojiModifier: bool,
    isEmojiModifierBase: bool,
    standalone: u2,
    zeroInGrapheme: bool,
};

pub const GraphemeProperties = packed struct(u7) {
    gcb: GraphemeClass,
    incb: IndicConjunctBreak,
    extendedPictographic: bool,
};

pub const CaseFold = struct {
    codepoints: [3]u21,
    len: u2,
    pub fn slice(self: *const CaseFold) []const u21;
};
pub const GraphemeState = struct { /* copyable checkpoint state */ };
pub fn graphemeBreak(previous: u21, current: u21, state: *GraphemeState) bool;
```

Spans describe `bytes[start.value..end.value]` in the view's input slice.
Offsets count bytes; columns count display cells. `isAscii` is a byte-range
test: empty input and every ASCII control byte, including NUL, ESC, and DEL,
count as ASCII; a high byte fails the check whether it belongs to valid UTF-8
or to malformed input. It is not UTF-8 validation and not a printable-text
check. `std.ascii.isAscii` checks one byte; this checks a whole slice with a
vectorized scan (SIMD where the target supports it) and a scalar tail.

`cp(value).width()` is a flat, per-scalar lookup: it does not group combining
marks or multi-scalar sequences with a base. Summing it over a string's
scalars is a different, narrower question than `Text.width()` and disagrees
with it on exactly the inputs that motivate grapheme clustering -- a
combining mark or a conjunct's vowel sign reports its own nonzero width here,
while `Text.width()` folds it into the cluster it belongs to. Prefer
`text(bytes).width()` for text; reach for `cp(value).width()` when working with
a code point that did not come from `Text`, or read it directly off
`point.width()` while iterating `codepoints()`.

`cp(value).grapheme()` is the per-code-point data `Text.graphemes()` clusters
with -- not a boundary decision by itself, since a real decision also needs
the state carried between code points. Reach for it to build a different
segmentation on code points that did not come from `Text`; use
`Text.graphemes()` for the common case, which already applies the full rules.
For codepoint-at-a-time input, initialize `GraphemeState` with `.{};` and call
`graphemeBreak(previous, current, &state)` for each adjacent pair. The first
call seeds `previous`; later calls pass the prior `current` again, and the state
does not consume it twice. A `true` result means a boundary occurs before
`current` and leaves the state ready for that new cluster. Copy the state to
checkpoint speculative input and restore the copy to undo it. Controls retain
default UAX #29 behavior; values above `max_codepoint` form independent
boundaries and clear carried context.

`cp(value).isEastAsianWide()` answers a different question than `cp(value).width()`: a
combining mark measures zero columns even when this is `true`, and a
Halfwidth scalar (which this also counts as wide) measures one column
despite it, since `cp(value).width()` only treats Wide and Fullwidth as two
columns.

`cp(value).fullCaseFold()` folds one code point using Unicode's full default C/F mapping.
The returned `CaseFold` owns its fixed `[3]u21` storage and allocates nothing;
retain the value while using `slice()`. Full mappings take precedence over
common mappings, Turkic alternatives are excluded, and unmapped or
out-of-range `u21` values return themselves. Folding is separate from
normalization and locale-sensitive casing.

`cp(value).general()` returns General_Category and thirteen
DerivedCoreProperties flags in one lookup. These are scalar facts with no
clustering or context. `isUppercase` also covers some `Nl`/`So` code points
but not `Lt`; `isGraphemeExtend` differs from `grapheme().gcb == .extend` on
five code points in Unicode 17.0.0. See the field comments in
[src/cp/cp.zig](../src/cp/cp.zig) for details.

`cp(value).terminal()` returns East Asian width, emoji flags, and terminal
width facts in one lookup. `standalone` follows the pinned uucode convention
and may be 3 (U+2E3B); `zeroInGrapheme` is a separate continuation fact.
This differs from `cp(value).width()`, which returns zunic's scalar width
in the range 0–2. For values above `max_codepoint`, the terminal group returns
neutral East Asian width, false emoji flags, standalone width 1, and
`zeroInGrapheme = true`. The general group returns `.cn` with false flags;
the grapheme group returns `.other`, `.none`, and false. Construction accepts
all `u21` values without validation.

The view stores only the code point; construction performs no lookup. Each
group fetches its own packed record. Retain a group when reading several fields:

```zig
const point = zunic.cp(0x1f600);
const p = point.general();
const t = point.terminal();
const g = point.grapheme();
// p.category == .so
// t.isEmojiPresentation == true
// g.extendedPictographic == true
```

The former free scalar functions are replaced by this view. For example,
`zunic.generalCategory(value)` becomes `zunic.cp(value).general().category`,
and `zunic.terminalProperties(value)` becomes `zunic.cp(value).terminal()`.
`WidthProperties` is absorbed into `TerminalProperties`; aggregate fields use
camelCase, including `point.grapheme().extendedPictographic`.

## Detailed documentation

- [Text](text/README.md): operation pages with signatures, examples, standards, and implementation decisions.
- [Shared conventions](conventions.md): borrowing, offsets, buffers, and error behavior.

[Architecture](internals/README.md) explains the shared property data, build options,
and verification strategy. Implementation pages describe the current source;
table sizes and private engine types are not public API promises.

Examples assume `const zunic = @import("zunic");` and
`const std = @import("std");` in a module that imports the Zunic dependency.
The runnable versions are in [examples.zig](examples.zig), covered by
`zig build docs-test` and `zig build test` from the repository root.

These pages cover the Text view. The separately exported `utf8`,
`line_break`, and `testing` namespaces are lower-level facilities; see their
source documentation when composing custom scanners or work-bound tests.

`text(bytes).isWhitespace(span)` answers the same `White_Space` question
`Text.trim()` uses for any span you already have. See
[trim](text/trim/README.md#the-predicate-itself).
