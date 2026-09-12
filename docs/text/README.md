# Text view

[Documentation index](../README.md) · [Shared conventions](../conventions.md)

**If you have UTF-8 text in a `[]const u8`, use `zunic.text(bytes)` to work
with its codepoints, grapheme clusters, words, or display lines.** You can
also measure its display width, trim whitespace, and normalize it.

```zig
const view = zunic.text("Hello, 世界!");
const columns = view.width(); // 12 display columns
var it = view.codepoints().iterator();
while (it.next()) |point| {
    std.debug.print("U+{X}\n", .{point.value});
}
// Output:
// U+48
// U+65
// U+6C
// U+6C
// U+6F
// U+2C
// U+20
// U+4E16
// U+754C
// U+21
```

`text()` borrows the input: opening the view does not scan, validate, copy,
or allocate. Its `.bytes` field holds the original slice. Keep that storage
alive and unchanged while using the view or its iterators.

If you already have a single `u21` value, use the
[codepoint view](../codepoint/README.md) to query its properties.

## Operations

Choose an operation based on what you need from the bytes:

| Task | Method | Documentation |
| --- | --- | --- |
| Read individual Unicode values | `codepoints()` | [Codepoints](codepoints/README.md) |
| Iterate grapheme clusters, such as a letter with combining marks | `graphemes()` | [Graphemes](graphemes/README.md) |
| Measure total display columns | `width()` | [Width](width/README.md) |
| Fit text into display lines | `wrap(options)` | [Wrap](wrap/README.md) |
| Remove whitespace from either end | `trim()`, `trimStart()`, `trimEnd()` | [Trim](trim/README.md) |
| Check whether a span is exactly one whitespace scalar | `isWhitespace(span)` | [Whitespace predicate](trim/README.md#the-predicate-itself) |
| Check whether all bytes are ASCII | `isAscii()` | [Validation and ASCII](#entry-point-and-validation) |
| Find hard line endings | `terminators()` | [Terminators](terminators/README.md) |
| Partition words and separators | `wordBounds()` | [Word boundaries](word-bounds/README.md) |
| Produce NFC, NFD, NFKC, or NFKD | `normalize(form)` | [Normalization](normalization/README.md) |
| Size a normalization output buffer | `normalizedLenBound(form)` | [Normalization](normalization/README.md) |
| Compare equivalent text or check normalization | `eql(other, how)`, `isNormalized(form)`, `isNormalizedQuick(form)` | [Normalization](normalization/README.md) |

`codepoints()`, `graphemes()`, `wordBounds()`, `terminators()`, and
`wrap(options)` return views; call `.iterator()` and then `.next()` to
traverse their results. `normalize(form)` returns an iterator directly.
Each operation page describes its result types, examples, and limits.

## Entry point and validation

```zig
pub fn text(bytes: []const u8) Text;
pub fn validate(self: Text) error{InvalidUtf8}!void;
pub fn isAscii(self: Text) bool;
```

**`zunic.text(bytes)` does not validate, copy, or allocate.**
It creates a view that borrows the existing bytes.

Methods handle malformed UTF-8 according to their own contracts:
grapheme, word, width, wrap, and trim operations tolerate it;
[Codepoint iteration](codepoints/README.md#malformed-input) stops at it and
records `err = .invalid_utf8` with its byte `offset`; normalization reports an
error when it encounters it. Terminators scan exact byte sequences.

If you want to reject malformed input before processing it, call
`try view.validate()`. Validation is fast, but it is still an additional scan:
valid input must be checked in full. It returns `InvalidUtf8` on malformed
input. The result is not cached, and validation does not change how later
methods work or let them skip their own decoding.

Zunic already includes optimizations for plain ASCII text. Use
`view.isAscii()` when you want to select your own ASCII fast path or reject
non-ASCII input. It returns true if every byte is below `0x80`. A false result
can mean valid non-ASCII UTF-8 or malformed input; it does not distinguish
them.

Empty input and ASCII control bytes, including NUL, ESC, and DEL, count as
ASCII. This is not a printable-text check. Each call scans until it finds a
non-ASCII byte or reaches the end; the result is not cached.

See the [API overview](../README.md#text) for all signatures and result types.

## Use a returned Text

Trimming returns a Text view over a smaller slice. Print its `.bytes`, call
another Text method, or create an iterator:

```zig
const view = zunic.text("  cafe\u{0301}  ").trim();
std.debug.print("{s}\n", .{view.bytes});
try std.testing.expectEqual(@as(usize, 4), view.width());
var it = view.graphemes().iterator();
while (it.next()) |span| {
    std.debug.print("{s}\n", .{view.bytes[span.start.value..span.end.value]});
}
// Output:
// café
// c
// a
// f
// é
```

Offsets from this iterator index `view.bytes`, starting at zero in the trimmed
slice. They do not index the original padded input.

Text does not interpret ANSI escapes; remove them before measuring styled
input. Width measures display cells under Zunic's fixed policy and does not
measure a font or reconstruct a terminal screen.

## Standards used

Unicode data is pinned to **17.0.0**. Each operation page describes its support
and limits:

| Standard | Used by |
| --- | --- |
| UAX #29: Unicode Text Segmentation | Graphemes and word boundaries; grapheme boundaries in width and wrap |
| UAX #14: Unicode Line Breaking Algorithm | Wrapping and hard terminators |
| UAX #11: East Asian Width | Width properties for display columns and wrapping |
| UAX #15: Unicode Normalization Forms | NFC, NFD, NFKC, NFKD, canonical/compatibility equality, and normalization checks |
| UAX #44: Unicode Character Database | The `White_Space` property used by trim and whitespace predicates |

`validate()` checks UTF-8 encoding directly. It does not run a UAX algorithm.
