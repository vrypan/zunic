# Width

[Text view](../README.md) · [Documentation index](../../README.md) · [Implementation](implementation.md)

Use `zunic.text(bytes).width()` to measure the total display columns of a
UTF-8 string. It measures grapheme clusters, including combining sequences
and emoji. For a single value, see
[codepoint width](../../codepoint/README.md#width-whitespace-and-case-folding).

The method scans the borrowed bytes without copying or allocating.
It does not validate the text in advance. Malformed bytes contribute no
width of their own; call [validate()](../README.md#entry-point-and-validation)
first if you want to reject them.

## API

```zig
pub fn width(self: Text) usize;
```

Returns the sum of terminal columns across the text's extended grapheme
clusters. Empty input measures zero.
The return value is a plain `usize`, unlike `Line.columns`, which is a `Column`.

## Example

```zig
std.debug.print("{d}\n", .{zunic.text("e\u{0301}界").width()});
std.debug.print("{d}\n", .{zunic.text("🇬🇷").width()});
std.debug.print("{d}\n", .{zunic.text("a\nb").width()});
std.debug.print("{d}\n", .{zunic.text("\t\xff").width()});
// Output:
// 3
// 2
// 2
// 0
```

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

## Unicode standards

`width()` uses Unicode 17.0.0 East Asian Width data described in
[UAX #11: East Asian Width, revision 45](https://www.unicode.org/reports/tr11/tr11-45.html)
and groups characters using the extended grapheme rules from
[UAX #29, revision 47](https://www.unicode.org/reports/tr29/tr29-47.html).
The final column count follows Zunic's [display policy](#display-policy).
UAX #11 supplies width properties; it does not prescribe a complete
terminal-width algorithm.
