# Trim

[Text view](../README.md) · [Documentation index](../../README.md) · [Implementation](implementation.md)

## Unicode standards

`trim()`, `trimStart()`, and `trimEnd()` remove the code points with the
Unicode 17.0.0 `White_Space` property, as published in the UCD data file
[PropList.txt](https://www.unicode.org/Public/17.0.0/ucd/PropList.txt) and
described by [UAX #44](https://www.unicode.org/reports/tr44/tr44-37.html).

Trimming is a Zunic operation over that property. It is not a segmentation or
line-breaking algorithm, and neither UAX #29 nor UAX #14 prescribes it. The
property is also not general category `Zs`, not `Pattern_White_Space`, not the
set of zero-width characters, and not the set of permissible line breaks.

## API

```zig
pub fn trim(self: Text) Text;
pub fn trimStart(self: Text) Text;
pub fn trimEnd(self: Text) Text;
```

Each returns another `Text` borrowing a sub-slice of the same bytes. There are
no options, no allocation, no copying, no output buffer, no iterator, and no
errors. Print the result with `.bytes`:

```zig
const input = "\u{00a0} Hello, 世界! \n";
const trimmed = zunic.text(input).trim();
std.debug.print("{s}\n", .{trimmed.bytes}); // Hello, 世界!
std.debug.print("width: {d}\n", .{trimmed.width()}); // 12
```

`trim()` removes whitespace from both ends, `trimStart()` from the beginning
only, and `trimEnd()` from the end only. `trimStart()` never inspects the far
end, and `trimEnd()` never scans from the beginning.

### The whitespace set

Exactly 25 code points:

| Code points | Name | UTF-8 |
| --- | --- | --- |
| U+0009..U+000D | TAB, LF, VT, FF, CR | `09`..`0D` |
| U+0020 | SPACE | `20` |
| U+0085 | NEXT LINE | `C2 85` |
| U+00A0 | NO-BREAK SPACE | `C2 A0` |
| U+1680 | OGHAM SPACE MARK | `E1 9A 80` |
| U+2000..U+200A | EN QUAD..HAIR SPACE | `E2 80 80`..`E2 80 8A` |
| U+2028 | LINE SEPARATOR | `E2 80 A8` |
| U+2029 | PARAGRAPH SEPARATOR | `E2 80 A9` |
| U+202F | NARROW NO-BREAK SPACE | `E2 80 AF` |
| U+205F | MEDIUM MATHEMATICAL SPACE | `E2 81 9F` |
| U+3000 | IDEOGRAPHIC SPACE | `E3 80 80` |

The no-break spaces U+00A0 and U+202F are trimmed: `White_Space` is about the
character's role, not about whether a line may break at it.

These are **not** trimmed, although several of them render as nothing:
U+200B ZERO WIDTH SPACE, U+FEFF ZERO WIDTH NO-BREAK SPACE (BOM), U+180E
MONGOLIAN VOWEL SEPARATOR, U+2060 WORD JOINER, U+0000 NUL, U+007F DEL, and
every combining mark.

### The predicate itself

```zig
pub fn isWhitespace(cp: u21) bool;
pub fn isWhitespaceSlice(glyph: []const u8) bool;

// Text
pub fn isWhitespace(self: Text, span: anytype) bool;
```

The scalar test behind all three trim methods is exported as
`zunic.cp(value).isWhitespace()`, for code working with a decoded code point directly.
Most span-shaped code should reach for `text(bytes).isWhitespace(span)`
instead -- `span` can be a `Span` returned by `Graphemes.iterator()` or a
`MeasuredSpan` from `.measured().iterator()`; anything with `start`/`end`
byte offsets works. It slices `bytes[span.start.value..span.end.value]` and
confirms that slice is exactly one whitespace scalar, not merely a span that
starts with one:

```zig
const view = zunic.text(bytes);
var graphemes = view.graphemes().iterator();
while (graphemes.next()) |span| {
    if (view.isWhitespace(span)) continue;
    std.debug.print("grapheme: {s}\n", .{bytes[span.start.value..span.end.value]});
}
```

`span` is assumed to index `self.bytes`; a span from a different byte slice
gives a meaningless answer rather than an error. This is a correct, if not
always interesting, question for a span that was never grapheme content:
every single-scalar UAX #14 hard terminator (LF, VT, FF, CR, NEL, LS, PS) is
also `White_Space`, so its `Terminators` span answers `true` -- except CRLF,
the one terminator that is two scalars, which like any other two-scalar span
answers `false`. `isWhitespaceSlice` is the primitive both build on, exported
directly for a byte slice that did not come from a span at all.

### Borrowed lifetime and offsets

The result borrows the caller's storage, exactly as `text()` does. Keep it
alive and unchanged for as long as the trimmed view or any iterator over it is
in use.

Offsets from the returned view are relative to **its** bytes, not to the
untrimmed input:

```zig
const trimmed = zunic.text("  hi  ").trim();
var it = trimmed.graphemes().iterator();
const first = it.next().?;
// first.start.value == 0, indexing trimmed.bytes, not the padded input.
```

To recover a position in the original input, compare the two slice pointers
yourself; the view does not carry an origin offset.

### Empty results

Empty input returns an empty view, and so does all-whitespace input. Removing
nothing returns the original slice unchanged, pointer and length. The borrowed
location of an empty result is preserved rather than replaced by an unrelated
empty literal: because `trim()` scans the start first, `trim()` and
`trimStart()` of all-whitespace input return `bytes[bytes.len..]`, while
`trimEnd()` returns `bytes[0..0]`.

### Code points, not graphemes

Trimming decides scalar by scalar. A leading space followed by a combining
mark loses the space and keeps the mark, even though the two are one grapheme
cluster:

```zig
try std.testing.expectEqualStrings("\u{0301}x", zunic.text(" \u{0301}x").trim().bytes);
```

### Malformed input

Trimming never validates the input and never returns an error. Interior bytes
are not examined at all, so interior whitespace and interior malformed UTF-8
are both untouched.

At each scanned edge the scan stops at the first scalar that is neither
whitespace nor decodable. Malformed bytes are preserved: not skipped, not
replaced, not reported.

```zig
try std.testing.expectEqualStrings("\xff", zunic.text(" \xff ").trim().bytes);
```

The two ends are independent. Invalid bytes at the start do not prevent
`trim()` from removing valid whitespace at the end, and vice versa. Call
`try view.validate()` explicitly when strict input is required; trimming
introduces no validation of its own and does not change how any other
operation treats malformed input.

### Escapes

Escape bytes get no special treatment. `ESC` ends a scan like any other
content, so `"  \x1b[31mred\x1b[0m  "` trims to `"\x1b[31mred\x1b[0m"` with the
sequences intact. Remove escapes before opening the text view when working
with styled input.

## Example: chaining

```zig
const trimmed = zunic.text("  cafe\u{0301} \u{3000}").trim();
try std.testing.expectEqualStrings("cafe\u{0301}", trimmed.bytes);
try std.testing.expectEqual(@as(usize, 4), trimmed.width());
try std.testing.expect(try trimmed.eql("caf\u{00E9}", .canonical));
var buffer: [16]u8 = undefined;
try std.testing.expectEqualStrings("caf\u{00E9}", try trimmed.normalize(.nfc).writeTo(&buffer));
```
