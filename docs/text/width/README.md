# Width

[Text view](../README.md) · [Documentation index](../../README.md) · [Implementation](implementation.md)

## Unicode standards

`width()` uses Unicode 16.0.0 East Asian Width data described in
[UAX #11: East Asian Width, revision 43](https://www.unicode.org/reports/tr11/tr11-43.html)
and groups characters using the extended grapheme rules from
[UAX #29, revision 45](https://www.unicode.org/reports/tr29/tr29-45.html).
The final column count follows Zunic's policy below. UAX #11 supplies width
properties; it does not prescribe a complete terminal-width algorithm.

## API

```zig
pub fn width(self: Text) usize;
```

Returns the sum of terminal columns across the text's extended grapheme
clusters. This performs a scan without allocating. Empty input measures zero.
The return value is a plain `usize`, unlike `Line.columns`, which is a `Column`.

## Display policy

| Input | Measurement |
| --- | --- |
| Printable ASCII | One column per byte |
| Combining marks without a base | Zero |
| Wide/fullwidth scalar bases | Two per base before cluster aggregation |
| East Asian ambiguous characters | Narrow under the pinned width policy |
| Pictographic or regional-indicator cluster with a base | Two per cluster |
| Ordinary cluster whose base widths sum to one or two | That sum |
| Ordinary cluster whose base widths sum beyond two | One replacement column |
| C0 controls, DEL, and malformed bytes themselves | Zero |

Width follows the generated scalar properties and cluster policy; it does not
query the terminal, apply locale settings, or shape glyphs. The pictographic
rule is broad: do not assume exact agreement with every terminal's emoji or
variation-selector rendering.

The zero-width scalar categories are nonspacing marks (`Mn`), enclosing marks
(`Me`), and format characters (`Cf`), except soft hyphen (U+00AD), which keeps
one column. C1 controls, including NEL, and Unicode line/paragraph separators
are not covered by the C0/DEL filter and currently measure one column each.
Wrapping removes hard terminators from line slices before reporting line width.

Zero-width input remains present in the original bytes. This function neither
sanitizes text nor returns a rendered string. To distinguish ordinary clusters
from replacement cases, inspect
[`graphemes().measured()`](../graphemes/README.md).

CR, LF, and tab contribute zero. This is **not** the final cursor
column or the maximum width of any line. For multiline layout, split at
[terminators](../terminators/README.md) and measure each gap.

## Example

```zig
try std.testing.expectEqual(@as(usize, 3), zunic.text("e\u{0301}界").width());
try std.testing.expectEqual(@as(usize, 2), zunic.text("🇬🇷").width());
try std.testing.expectEqual(@as(usize, 2), zunic.text("a\nb").width());
try std.testing.expectEqual(@as(usize, 0), zunic.text("\t\xff").width());
```
