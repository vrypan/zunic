# Zunic documentation

Zunic provides allocation-free operations over borrowed bytes. Choose the view
that matches the input:

| View | Entry point | Operations |
| --- | --- | --- |
| [Text](text/README.md) | `zunic.text(bytes)` | Graphemes, width, wrapping, trimming, terminators, words, normalization, validation |
| [Terminal](terminal/README.md) | `zunic.terminal(bytes)` | Grapheme and escape tokens, formatting state, ANSI stripping |

Both expose their borrowed input as `.bytes`. To use plain-text operations on
styled input, call `terminal(bytes).stripAnsi(buffer)`, then `text(plain)` on the
returned bytes. See [shared conventions](conventions.md) for lifetimes and offsets.

## API overview

The signatures use names exported by `zunic`, grouped by their owning view.
They are an overview, not a standalone Zig file. `form` and `how` are compile-time
arguments. Unicode data is pinned to **16.0.0**.

```zig
pub const unicode_version: std.SemanticVersion; // 16.0.0
pub fn text(bytes: []const u8) Text;
pub fn terminal(bytes: []const u8) Terminal;
```

### Text

```zig
// Text methods
pub fn validate(self: Text) error{InvalidUtf8}!void;
pub fn graphemes(self: Text) Graphemes;
pub fn width(self: Text) usize;
pub fn wrap(self: Text, options: WrapOptions) error{InvalidWidth}!Wrapped;
pub fn trim(self: Text) Text;
pub fn trimStart(self: Text) Text;
pub fn trimEnd(self: Text) Text;
pub fn isWhitespace(self: Text, span: anytype) bool;
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
pub const Form = enum { nfc, nfd };
pub const Equivalence = enum { canonical };
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
```

Columns follow Zunic's cell width policy. `.grapheme` allows wrapping
inside an otherwise unbreakable word; `.allow` lets it exceed the limit.
Neither splits an individual grapheme. A zero width is `InvalidWidth`.
`isWhitespace(span)` accepts a `Span` or `MeasuredSpan` from the same Text slice.

`isNormalizedQuick()` scans the whole input and can return `.maybe`;
`isNormalized()` resolves the answer to a boolean and may stop early.
NFKC/NFKD and stream-safe normalization are not available.

### Terminal

```zig
pub fn tokens(self: Terminal) TerminalTokens;
pub fn stripAnsi(self: Terminal, buffer: []u8) error{NoSpace}![]u8;
```

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
```

Spans describe `bytes[start.value..end.value]` in the view's input slice.
Offsets count bytes; columns count display cells.

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
