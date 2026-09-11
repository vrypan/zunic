# Text view

[Documentation index](../README.md) · [Terminal view](../terminal/README.md) · [Shared conventions](../conventions.md)

`zunic.text(bytes)` opens a borrowed view for plain-text Unicode operations.
Opening it does not scan, validate, copy, or allocate. The input is available as
`Text.bytes`; keep its storage alive and unchanged while using the view or its
iterators.

## Entry point and validation

```zig
pub fn text(bytes: []const u8) Text;
pub fn validate(self: Text) error{InvalidUtf8}!void;
```

`try view.validate()` checks the complete slice and returns `InvalidUtf8` if it
is malformed. It does not change the view or later operations. Grapheme,
codepoint, word, width, wrap, and trim operations tolerate malformed UTF-8;
normalization reports it when encountered. Terminators scan exact byte
sequences.

`view.isAscii()` is a different, narrower question: a plain byte-range test
(every byte below `0x80`), not a UAX algorithm and not UTF-8 validation. Empty
input and every ASCII control byte, including NUL, ESC, and DEL, count as
ASCII. It scans the whole slice on every call; there is no cache.

## Operations

| Method | Result | API and examples | Implementation |
| --- | --- | --- | --- |
| `graphemes()` | View of extended grapheme spans | [Graphemes](graphemes/README.md) | [Decisions](graphemes/implementation.md) |
| `codepoints()` | View of individual Unicode scalars | [API overview](../README.md#text) | -- |
| `width()` | Total display columns | [Width](width/README.md) | [Decisions](width/implementation.md) |
| `wrap(options)` | View of display lines | [Wrap](wrap/README.md) | [Decisions](wrap/implementation.md) |
| `trim()`, `trimStart()`, `trimEnd()` | Text over the retained bytes | [Trim](trim/README.md) | [Decisions](trim/implementation.md) |
| `isWhitespace(span)` | Whether a span contains exactly one whitespace scalar | [Whitespace predicate](trim/README.md#the-predicate-itself) | [Decisions](trim/implementation.md) |
| `isAscii()` | Whether every byte is below 0x80 | [API overview](../README.md#shared-positions-and-helpers) | -- |
| `terminators()` | View of hard line terminator spans | [Terminators](terminators/README.md) | [Decisions](terminators/implementation.md) |
| `wordBounds()` | View of word and non-word spans | [Word boundaries](word-bounds/README.md) | [Decisions](word-bounds/implementation.md) |
| `normalize(form)` | Normalization iterator with UTF-8 buffer output | [Normalization](normalization/README.md) | [Decisions](normalization/implementation.md) |
| `normalizedLenBound(form)` | Output capacity bound | [Normalization](normalization/README.md) | [Decisions](normalization/implementation.md) |
| `eql(other, how)`, `isNormalized(form)`, `isNormalizedQuick(form)` | Equality and normalization checks | [Normalization](normalization/README.md) | [Decisions](normalization/implementation.md) |

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
```

Offsets from this iterator index `view.bytes`, starting at zero in the trimmed
slice. They do not index the original padded input.

Text does not interpret ANSI escapes. For styled input, use
[`terminal(input).stripAnsi(buffer)`](../terminal/strip-ansi.md), then open a
Text view on the returned slice. Width measures display cells under Zunic's
fixed policy; it does not measure a font or reconstruct a terminal screen.

## Standards used

Unicode data is pinned to **16.0.0**. Each operation page describes its support
and limits:

| Standard | Used by |
| --- | --- |
| UAX #29: Unicode Text Segmentation | Graphemes and word boundaries; grapheme boundaries in width and wrap |
| UAX #14: Unicode Line Breaking Algorithm | Wrapping and hard terminators |
| UAX #11: East Asian Width | Width properties for display columns and wrapping |
| UAX #15: Unicode Normalization Forms | NFC, NFD, NFKC, NFKD, canonical/compatibility equality, and normalization checks |
| UAX #44: Unicode Character Database | The `White_Space` property used by trim and whitespace predicates |

`validate()` checks UTF-8 encoding directly. It does not run a UAX algorithm.
