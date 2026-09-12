# Trim

[Text view](../README.md) · [Documentation index](../../README.md) · [Implementation](implementation.md)

Use `zunic.text(bytes).trim()` to remove Unicode whitespace from both ends
of a byte string. Use `trimStart()` or `trimEnd()` to trim only one end.
The result is another `Text` view; read `.bytes` or call another text method
on it.

The result borrows a sub-slice of the existing bytes. Nothing is allocated,
copied, or modified. Scanning happens when you call the method, only at the
requested edges. Trimming does not validate the whole input; malformed bytes
stop an edge scan and remain in the result.

## API

```zig
pub fn trim(self: Text) Text;
pub fn trimStart(self: Text) Text;
pub fn trimEnd(self: Text) Text;
```

## Example

```zig
const input = "\u{00a0} Hello, 世界! \n";
const trimmed = zunic.text(input).trim();
std.debug.print("{s}\n", .{trimmed.bytes});
std.debug.print("width: {d}\n", .{trimmed.width()});
// Output:
// Hello, 世界!
// width: 12
```

`trim()` removes whitespace from both ends, `trimStart()` from the beginning
only, and `trimEnd()` from the end only. `trimStart()` never inspects the far
end, and `trimEnd()` never scans from the beginning.

## The whitespace set

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

## The predicate itself

```zig
pub fn isWhitespace(self: Text, span: anytype) bool;
```

Use `view.isWhitespace(span)` to check whether a span is exactly one Unicode
whitespace scalar. Pass a `Span` or `MeasuredSpan` from that view; the check
uses its `start` and `end` byte offsets. A space followed by a combining mark,
or CRLF as a pair, is not a single whitespace scalar.

For a `u21` value, use
[cp(value).isWhitespace()](../../codepoint/README.md#width-whitespace-and-case-folding).
For a byte slice without a span, use `zunic.isWhitespaceSlice(bytes)`.

```zig
const bytes = "a b";
const view = zunic.text(bytes);
var graphemes = view.graphemes().iterator();
while (graphemes.next()) |span| {
    if (view.isWhitespace(span)) continue;
    std.debug.print("grapheme: {s}\n", .{bytes[span.start.value..span.end.value]});
}
// Output:
// grapheme: a
// grapheme: b
```

The span must index the same view’s bytes and remain within their bounds.

## Borrowed lifetime and offsets

The result borrows the caller's storage, exactly as `text()` does. Keep it
alive and unchanged for as long as the trimmed view or any iterator over it is
in use.

Offsets from the returned view are relative to **its** bytes, not to the
untrimmed input:

```zig
const trimmed = zunic.text("  hi  ").trim();
var it = trimmed.graphemes().iterator();
const first = it.next().?;
std.debug.print("[{d}..{d}]\n", .{ first.start.value, first.end.value });
// Output:
// [0..1]
```

To recover a position in the original input, compare the two slice pointers
yourself; the view does not carry an origin offset.

## Empty results

Empty input and all-whitespace input return an empty view. Removing nothing
returns the original slice unchanged.

## Code points, not graphemes

Trimming decides scalar by scalar. A leading space followed by a combining
mark loses the space and keeps the mark, even though the two are one grapheme
cluster:

```zig
try std.testing.expectEqualStrings("\u{0301}x", zunic.text(" \u{0301}x").trim().bytes);
// Retained values: U+0301 followed by U+0078.
```

## Malformed input

Trimming never validates the input and never returns an error. Interior bytes
are not examined at all, so interior whitespace and interior malformed UTF-8
are both untouched.

At each edge, scanning stops on a non-whitespace scalar or an undecodable
sequence. Malformed bytes remain in the result without an error.

```zig
try std.testing.expectEqualStrings("\xff", zunic.text(" \xff ").trim().bytes);
// Retained bytes: FF. No error is returned.
```

The two ends are independent. Invalid bytes at the start do not prevent
`trim()` from removing valid whitespace at the end, and vice versa. Call
[validate()](../README.md#entry-point-and-validation) when strict input is required; trimming
introduces no validation of its own and does not change how any other
operation treats malformed input.

## Escapes

Escape bytes get no special treatment. `ESC` ends a scan like any other
content, so `"  \x1b[31mred\x1b[0m  "` trims to `"\x1b[31mred\x1b[0m"` with the
sequences intact. Remove escapes before opening the text view when working
with styled input.

You can chain [width](../width/README.md),
[normalization](../normalization/README.md), or iteration on the returned view.
Their offsets and results apply to the trimmed bytes.

## Unicode standards

`trim()`, `trimStart()`, and `trimEnd()` remove the code points with the
Unicode 17.0.0 `White_Space` property, as published in the UCD data file
[PropList.txt](https://www.unicode.org/Public/17.0.0/ucd/PropList.txt) and
described by [UAX #44](https://www.unicode.org/reports/tr44/tr44-37.html).

Trimming is a Zunic operation over that property. It is not a segmentation or
line-breaking algorithm, and neither UAX #29 nor UAX #14 prescribes it. The
property is also not general category `Zs`, not `Pattern_White_Space`, not the
set of zero-width characters, and not the set of permissible line breaks.
