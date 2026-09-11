# Zunic documentation

Zunic provides allocation-free operations over borrowed bytes. Choose the view
that matches the input:

| View | Entry point | Operations |
| --- | --- | --- |
| [Text](text/README.md) | `zunic.text(bytes)` | Graphemes, width, wrapping, trimming, terminators, words, normalization, validation, ASCII check |
| [Terminal](terminal/README.md) | `zunic.terminal(bytes)` | Grapheme and escape tokens, formatting state, ANSI stripping |

Both expose their borrowed input as `.bytes`. To use plain-text operations on
styled input, call `terminal(bytes).stripAnsi(buffer)`, then `text(plain)` on the
returned bytes. See [shared conventions](conventions.md) for lifetimes and offsets.

## API overview

The signatures use names exported by `zunic`, grouped by their owning view.
They are an overview, not a standalone Zig file. `form` and `how` are compile-time
arguments. Unicode data is pinned to **17.0.0**.

```zig
pub const unicode_version: std.SemanticVersion; // 17.0.0
pub fn text(bytes: []const u8) Text;
pub fn terminal(bytes: []const u8) Terminal;
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
normalization rejects it when encountered. Trimming returns another borrowed
Text, with offsets relative to its retained slice.

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
pub const Codepoint = struct {
    start: ByteOffset,
    end: ByteOffset,
    value: ?u21,
    width: u2,
    grapheme: GraphemeProperties,
    east_asian_wide: bool,
};
```

Columns follow Zunic's cell width policy. `.grapheme` allows wrapping
inside an otherwise unbreakable word; `.allow` lets it exceed the limit.
Neither splits an individual grapheme. A zero width is `InvalidWidth`.
`isWhitespace(span)` accepts a `Span` or `MeasuredSpan` from the same Text slice.
`isAscii()` scans the whole slice on every call, with no cache; it is a
byte-range test, not UTF-8 validation.

`codepoints()` yields one `Codepoint` per scalar, unlike `graphemes()`, which
groups combining marks and multi-scalar sequences with their base. A malformed
byte is never an error: it yields a `Codepoint` with `value = null` and
`end - start == 1`, the same one-byte recovery `graphemes()` and `width()` use.
`Codepoint.width` is the same flat lookup as `codepointWidth()`, `0` for
malformed input; see that function's docs for how it differs from `Text.width()`.
`Codepoint.grapheme` and `.east_asian_wide` are the same lookups as
`graphemeProperties()` and `isEastAsianWide()`; malformed input gets the
package's fixed fallback classification and `false`, respectively.

`isNormalizedQuick()` scans the whole input and can return `.maybe` for a
composing form (`.nfc`/`.nfkc`); a decomposing form (`.nfd`/`.nfkd`) never
does. `isNormalized()` resolves the answer to a boolean and may stop early.
`.nfkc`/`.nfkd` also decompose compatibility mappings (ligatures, fullwidth
forms, and similar) that `.nfc`/`.nfd` leave untouched; `eql(..., .compatibility)`
is the matching broader equivalence. Full default case folding is available
through `fullCaseFold()` as a separate scalar operation; it is not folded into
normalization or equality. Stream-safe normalization is not available.

### Terminal

```zig
pub fn isAscii(self: Terminal) bool;
pub fn tokens(self: Terminal) TerminalTokens;
pub fn stripAnsi(self: Terminal, buffer: []u8) error{NoSpace}![]u8;
```

`isAscii()` scans the raw bytes exactly as given: no escape parsing, no state
tracking, no restriction to visible content. An all-ASCII escape sequence
counts as ASCII even if incomplete; a non-ASCII byte inside an OSC payload
fails the check even though stripping would remove it. Scans the whole slice
every call, with no cache.

#### Terminal iterator

| View | Methods | Iterator result |
| --- | --- | --- |
| `TerminalTokens` | `.iterator()` | `next(self: *Self) error{EscapeInsideGrapheme}!?TerminalToken` |

The iterator exposes `state: TerminalState = .{}`, updated before returning an
SGR or OSC 8 token. See the [full state layout](terminal/state.md) for colors,
attributes, fonts, framing, scripts, ideogram marks, and borrowed links.

Tokens follow source order. If later content joins a grapheme across an escape,
`next()` returns `EscapeInsideGrapheme`; earlier tokens have already been emitted.
`stripAnsi()` removes recognized escapes without decoding UTF-8 or checking
grapheme boundaries. Its only error is `NoSpace`. See [tokens](terminal/tokens.md)
and [stripping](terminal/strip-ansi.md) for full error contracts.

#### Terminal results

```zig
pub const StyleFields = packed struct {
    foreground: bool = false,
    background: bool = false,
    underline_color: bool = false,
    bold: bool = false,
    faint: bool = false,
    italic: bool = false,
    fraktur: bool = false,
    inverse: bool = false,
    concealed: bool = false,
    strikethrough: bool = false,
    overline: bool = false,
    proportional: bool = false,
    underline: bool = false,
    blink: bool = false,
    frame: bool = false,
    font: bool = false,
    script: bool = false,
    ideogram: bool = false,
    unhandled: bool = false,
};

pub const Escape = struct {
    span: Span,
    effect: union(enum) { sgr: StyleFields, hyperlink, other },
};
pub const TerminalToken = union(enum) {
    grapheme: Span,
    escape: Escape,
};
```

### Shared positions and helpers

```zig
pub const ByteOffset = struct { value: usize };
pub const Column = struct { value: usize };
pub const Span = struct { start: ByteOffset, end: ByteOffset };

// Whitespace helpers for decoded scalars or byte slices.
pub fn isWhitespace(cp: u21) bool;
pub fn isWhitespaceSlice(glyph: []const u8) bool;

// Whether every byte in a slice is below 0x80. `Text.isAscii()` and
// `Terminal.isAscii()` are the same check on a view's own bytes.
pub fn isAscii(bytes: []const u8) bool;

// The terminal-cell width of one code point in isolation: 0, 1, or 2.
pub fn codepointWidth(cp: u21) u2;

// One code point's grapheme-break classification: the raw facts, not a
// boundary decision. See `Text.graphemes()` for the full UAX #29 rules.
pub const GraphemeClass = enum { other, cr, lf, control, extend, zwj, regional_indicator, prepend, spacingmark, l, v, t, lv, lvt };
pub const IndicConjunctBreak = enum { none, consonant, extend, linker };
pub const GraphemeProperties = struct {
    gcb: GraphemeClass,
    incb: IndicConjunctBreak,
    extended_pictographic: bool,
};
pub fn graphemeProperties(cp: u21) GraphemeProperties;

pub const max_codepoint: u21 = 0x10FFFF;
pub const EastAsianWidth = enum(u3) { neutral, fullwidth, halfwidth, wide, narrow, ambiguous };
pub const WidthProperties = struct {
    standalone: u2,
    zero_in_grapheme: bool,
    emoji_modifier: bool,
};
pub const CaseFold = struct {
    codepoints: [3]u21,
    len: u2,
    pub fn slice(self: *const CaseFold) []const u21;
};
pub const GraphemeState = struct { /* copyable checkpoint state */ };
pub fn eastAsianWidth(cp: u21) EastAsianWidth;
pub fn isEmojiPresentation(cp: u21) bool;
pub fn isEmojiVariationBase(cp: u21) bool;
pub fn isEmojiModifier(cp: u21) bool;
pub fn isEmojiModifierBase(cp: u21) bool;
pub fn widthProperties(cp: u21) WidthProperties;
pub fn fullCaseFold(cp: u21) CaseFold;
pub fn graphemeBreak(previous: u21, current: u21, state: *GraphemeState) bool;

// Whether a code point has East_Asian_Width Wide, Fullwidth, or Halfwidth.
pub fn isEastAsianWide(cp: u21) bool;

// General_Category and a fixed set of DerivedCoreProperties booleans. Unlike
// everything above, none of zunic's own engines read this data.
pub const GeneralCategory = enum { lu, ll, lt, lm, lo, mn, mc, me, nd, nl, no_, pc, pd, ps, pe, pi, pf, po, sm, sc, sk, so, zs, zl, zp, cc, cf, cs, co, cn };
pub const GeneralCategoryProperties = struct {
    category: GeneralCategory,
    is_alphabetic: bool,
    is_lowercase: bool,
    is_uppercase: bool,
    is_cased: bool,
    is_case_ignorable: bool,
    is_math: bool,
    is_id_start: bool,
    is_id_continue: bool,
    is_xid_start: bool,
    is_xid_continue: bool,
    is_default_ignorable: bool,
    is_grapheme_base: bool,
    is_grapheme_extend: bool,
};
pub fn generalCategoryProperties(cp: u21) GeneralCategoryProperties;
pub fn generalCategory(cp: u21) GeneralCategory;
pub fn isAlphabetic(cp: u21) bool;
pub fn isLowercase(cp: u21) bool;
pub fn isUppercase(cp: u21) bool;
pub fn isCased(cp: u21) bool;
pub fn isCaseIgnorable(cp: u21) bool;
pub fn isMath(cp: u21) bool;
pub fn isIdStart(cp: u21) bool;
pub fn isIdContinue(cp: u21) bool;
pub fn isXidStart(cp: u21) bool;
pub fn isXidContinue(cp: u21) bool;
pub fn isDefaultIgnorable(cp: u21) bool;
pub fn isGraphemeBase(cp: u21) bool;
pub fn isGraphemeExtend(cp: u21) bool;
```

Spans describe `bytes[start.value..end.value]` in the view's input slice.
Offsets count bytes; columns count display cells. `isAscii` is a byte-range
test: empty input and every ASCII control byte, including NUL, ESC, and DEL,
count as ASCII; a high byte fails the check whether it belongs to valid UTF-8
or to malformed input. It is not UTF-8 validation and not a printable-text
check. `std.ascii.isAscii` checks one byte; this checks a whole slice with a
vectorized scan (SIMD where the target supports it) and a scalar tail.

`codepointWidth` is a flat, per-scalar lookup: it does not group combining
marks or multi-scalar sequences with a base. Summing it over a string's
scalars is a different, narrower question than `Text.width()` and disagrees
with it on exactly the inputs that motivate grapheme clustering -- a
combining mark or a conjunct's vowel sign reports its own nonzero width here,
while `Text.width()` folds it into the cluster it belongs to. Prefer
`text(bytes).width()` for text; reach for `codepointWidth` when working with
a code point that did not come from `Text`, or read it directly off
`Codepoint.width` while iterating `codepoints()`.

`graphemeProperties` is the per-code-point data `Text.graphemes()` clusters
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

`isEastAsianWide` answers a different question than `codepointWidth`: a
combining mark measures zero columns even when this is `true`, and a
Halfwidth scalar (which this also counts as wide) measures one column
despite it, since `codepointWidth` only treats Wide and Fullwidth as two
columns.

`fullCaseFold` folds one code point using Unicode's full default C/F mapping.
The returned `CaseFold` owns its fixed `[3]u21` storage and allocates nothing;
retain the value while using `slice()`. Full mappings take precedence over
common mappings, Turkic alternatives are excluded, and unmapped or
out-of-range `u21` values return themselves. Folding is separate from
normalization and locale-sensitive casing.

`generalCategory` and the fourteen functions after it are General_Category
and `DerivedCoreProperties` booleans, generated solely to expose them -- no
existing engine in zunic reads this data, unlike everything documented above
it on this page. Each is a flat, per-code-point fact with no clustering and
no context. Several read as narrower or broader than their name suggests:
`isUppercase` also covers some `Nl`/`So` code points but not `Lt`;
`isGraphemeExtend` is the `DerivedCoreProperties` property, not
`graphemeProperties(cp).gcb == .extend` (they disagree on five code points
in Unicode 17.0.0). See each function's doc comment in `root.zig` for the
verified category list it actually spans. `generalCategoryProperties` is one
lookup for all fourteen facts; each `isXxx` function reads one field of it.

## Detailed documentation

- [Text](text/README.md): operation pages with signatures, examples, standards, and implementation decisions.
- [Terminal](terminal/README.md): [tokens](terminal/tokens.md), [formatting state](terminal/state.md), and [ANSI stripping](terminal/strip-ansi.md), with implementation notes and benchmarks.
- [Shared conventions](conventions.md): borrowing, offsets, buffers, and error behavior.

[Architecture](internals/README.md) explains the shared property data, build options,
and verification strategy. Implementation pages describe the current source;
table sizes and private engine types are not public API promises.

Examples assume `const zunic = @import("zunic");` and
`const std = @import("std");` in a module that imports the Zunic dependency.
The runnable versions are in [examples.zig](examples.zig), covered by
`zig build docs-test` and `zig build test` from the repository root.

These pages cover the Text and Terminal views. The separately exported `utf8`,
`line_break`, and `testing` namespaces are lower-level facilities; see their
source documentation when composing custom scanners or work-bound tests.

`text(bytes).isWhitespace(span)` answers the same `White_Space` question
`Text.trim()` uses, for any span you already have -- for example, an
escape-aware trim built over `Terminal.tokens()` that decides for itself
whether a styled space is content or padding. See
[trim](text/trim/README.md#the-predicate-itself).
