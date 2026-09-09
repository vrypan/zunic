# Zunic documentation

Zunic provides allocation-free Unicode operations over borrowed UTF-8 bytes.
Its Unicode data is pinned to **16.0.0**, exposed as `zunic.unicode_version`.

## API overview

The signatures below use names exported by `zunic`. Method declarations are
grouped by their owning type; they are an overview, not a standalone Zig file.
`form` and `how` are compile-time arguments.

```zig
pub const unicode_version: std.SemanticVersion; // 16.0.0
pub const Form = enum { nfc, nfd };
pub const Equivalence = enum { canonical };
pub const QuickCheck = enum { yes, no, maybe };
pub const NormalizationError = error{ InvalidUtf8, SequenceTooLong };
pub const NormalizationWriteError = NormalizationError || error{NoSpace};

// Free functions
pub fn text(bytes: []const u8) Text;
pub fn terminal(bytes: []const u8) Terminal;
pub fn NormalizationIterator(comptime form: Form) type;

// Text methods
pub fn validate(self: Text) error{InvalidUtf8}!void;
pub fn graphemes(self: Text) Graphemes;
pub fn width(self: Text) usize;
pub fn wrap(self: Text, options: WrapOptions) error{InvalidWidth}!Wrapped;
pub fn terminators(self: Text) Terminators;
pub fn wordBounds(self: Text) WordBounds;
pub fn normalize(self: Text, comptime form: Form) NormalizationIterator(form);
pub fn normalizedLenBound(self: Text, comptime form: Form) error{Overflow}!usize;
pub fn eql(self: Text, other: []const u8, comptime how: Equivalence) NormalizationError!bool;
pub fn isNormalized(self: Text, comptime form: Form) NormalizationError!bool;
pub fn isNormalizedQuick(self: Text, comptime form: Form) error{InvalidUtf8}!QuickCheck;

// Terminal methods (first draft)
pub fn graphemes(self: Terminal) TerminalGraphemes;
```

`text()` borrows the bytes without scanning or allocating. `validate()` checks
the complete slice. Grapheme, word, width, and wrap operations tolerate invalid
UTF-8; normalization rejects it when encountered. The quick normalization check
always scans the whole input and can return `.maybe`; `isNormalized()` resolves
the answer to a boolean and may stop early. See [conventions](conventions.md)
and [normalization](normalization/README.md) for the error and buffer contracts.

`terminal()` also borrows without scanning. Its initial grapheme iterator skips
complete supported CSI/OSC escapes while keeping original byte offsets. It
returns `EscapeInsideGrapheme` if an escape splits a grapheme; successful spans
exclude recognized escapes. Formatting state, width,
stripping, and wrapping are pending; see the [terminal draft](terminal/README.md).

### Views and iterators

Call `.iterator()` on a view, then `.next()` until it returns `null`.
Grapheme and wrapped iterator types are inferred; their internal type names
are not exported by `zunic`. `Self` below means the corresponding iterator.

| View | Methods | Iterator result |
| --- | --- | --- |
| `Graphemes` | `.iterator()`, `.measured() → MeasuredGraphemes` | `next(self: *Self) ?Span` |
| `TerminalGraphemes` | `.iterator()` | `next(self: *Self) error{EscapeInsideGrapheme}!?Span` |
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

### Options and results

```zig
pub const Overflow = enum { allow, grapheme };
pub const WrapOptions = struct {
    max_columns: usize,
    overflow: Overflow = .grapheme,
};
pub const ByteOffset = struct { value: usize };
pub const Column = struct { value: usize };
pub const Span = struct { start: ByteOffset, end: ByteOffset };
pub const MeasuredSpan = struct {
    start: ByteOffset,
    end: ByteOffset,
    columns: u2,
    renderable: bool,
};
pub const Line = struct { start: ByteOffset, end: ByteOffset, columns: Column };
pub const WordBound = struct { start: ByteOffset, end: ByteOffset, is_word: bool };
```

Offsets describe `bytes[start.value..end.value]` in the original input.
Columns follow Zunic's terminal width policy. `.grapheme` allows wrapping
inside an otherwise unbreakable word; `.allow` lets it exceed the limit.
Neither splits an individual grapheme cluster. A zero width is `InvalidWidth`.

NFKC/NFKD and stream-safe normalization are not available in the current API.

## Detailed documentation

| Operation | API and examples | Implementation decisions |
| --- | --- | --- |
| Extended grapheme clusters | [graphemes](graphemes/README.md) | [Compiled transitions and shared measurement](graphemes/implementation.md) |
| Terminal columns | [width](width/README.md) | [Width policy and ASCII detection](width/implementation.md) |
| Greedy display lines | [wrap](wrap/README.md) | [Fused scanning, bounded work, and fast paths](wrap/implementation.md) |
| Hard line terminators | [terminators](terminators/README.md) | [Why byte scanning is sufficient](terminators/implementation.md) |
| Default word boundaries | [wordBounds](word-bounds/README.md) | [Decision tables and selective lookahead](word-bounds/implementation.md) |
| NFC/NFD and canonical equality | [normalization](normalization/README.md) | [Bounded runs and quick checks](normalization/implementation.md) |
| Terminal graphemes (draft) | [terminal](terminal/README.md) | [Escape scanning and next steps](terminal/implementation.md) |

[Architecture](architecture.md) explains the shared property data, build options,
and verification strategy. Implementation pages describe the current source;
table sizes and private engine types are not public API promises.

Examples assume `const zunic = @import("zunic");` and
`const std = @import("std");` in a module that imports the Zunic dependency.
The runnable versions are in [examples.zig](examples.zig), covered by
`zig build docs-test` and `zig build test` from the repository root.

These pages cover the text-facing API. The separately exported `utf8`,
`line_break`, and `testing` namespaces are lower-level facilities; see their
source documentation when composing custom scanners or work-bound tests.
