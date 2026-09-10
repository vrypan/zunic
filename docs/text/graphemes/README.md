# Graphemes

[Text view](../README.md) · [Documentation index](../../README.md) · [Implementation](implementation.md)

## Unicode standards

`graphemes()` uses the default extended grapheme cluster rules from
[UAX #29: Unicode Text Segmentation, revision 45](https://www.unicode.org/reports/tr29/tr29-45.html),
for Unicode 16.0.0. Both plain and measured iterators use those boundaries.
Measured columns also use East Asian Width data from
[UAX #11, revision 43](https://www.unicode.org/reports/tr11/tr11-43.html),
with [Zunic's width policy](../width/README.md#display-policy).
UAX #29 does not define terminal column counts.

## API

```zig
pub fn graphemes(self: Text) Graphemes;

// Graphemes
pub fn iterator(self: Graphemes) Iterator(false);
pub fn measured(self: Graphemes) MeasuredGraphemes;

// MeasuredGraphemes
pub fn iterator(self: MeasuredGraphemes) Iterator(true);

// Returned iterators, respectively
pub fn next(self: *@This()) ?Span;
pub fn next(self: *@This()) ?MeasuredSpan;
```

Segments default extended grapheme clusters using Unicode 16 UAX #29 rules.
A cluster can contain several scalars: an accented letter, a flag, or an emoji
ZWJ sequence can each be one result. This is useful for cursor movement and
grapheme-safe slicing; it is not a promise about how a font renders the text.

`Graphemes` and `MeasuredGraphemes` contain a borrowed `bytes: []const u8`.
`Iterator(false)` and `Iterator(true)` are the concrete types returned by the
view methods in `text.zig`; they are not named exports on `zunic`. Normally let
Zig infer their types. Both iterators exhaust with `null`. Empty input yields
no spans. Spans partition the complete input, including controls and malformed
bytes; adjacent offsets meet without gaps.

## Measured results

```zig
pub const MeasuredSpan = struct {
    start: ByteOffset,
    end: ByteOffset,
    columns: u2,
    renderable: bool,
};
```

`columns` is the cluster's terminal width: zero, one, or two. `renderable`
indicates whether the original cluster fits Zunic's display policy. Base-less
clusters, C0 controls, DEL, and standalone malformed bytes yield zero and `false`.
A cluster whose ordinary base widths sum beyond two yields one and `false`:
that is a replacement-cell measurement, not a rewritten byte sequence.
Pictographic and regional-indicator clusters with a base measure two.
See [width policy](../width/README.md) before using this as a rendering decision.

## Example

```zig
const bytes = "e\u{0301}界";
var it = zunic.text(bytes).graphemes().measured().iterator();
const accent = it.next().?;
try std.testing.expectEqualStrings("e\u{0301}", bytes[accent.start.value..accent.end.value]);
try std.testing.expectEqual(@as(u2, 1), accent.columns);
const ideograph = it.next().?;
try std.testing.expectEqual(@as(u2, 2), ideograph.columns);
try std.testing.expect(it.next() == null);
```

For boundaries alone, omit `.measured()`: the returned `Span` contains only
`start` and `end`. Neither form normalizes the bytes.
