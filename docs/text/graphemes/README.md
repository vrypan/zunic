# Graphemes

[Text view](../README.md) · [Documentation index](../../README.md) · [Implementation](implementation.md)

Use `zunic.text(bytes).graphemes().iterator()` to iterate over a byte string,
returning one grapheme's byte span at a time. Add `.measured()` before
`.iterator()` when you also need each grapheme's display width.

Opening the view and iterator does not validate, copy, or allocate. They
borrow the original bytes; keep those bytes alive and unchanged while using
them. Segmentation happens as you call `next()`.

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

Segments default extended grapheme clusters using Unicode 17 UAX #29 rules.
A cluster can contain several scalars: an accented letter, a flag, or an emoji
ZWJ sequence can each be one result. This is useful for cursor movement and
grapheme-safe slicing; it is not a promise about how a font renders the text.

Let Zig infer the iterator type. Both iterators exhaust with `null`. Empty
input yields no spans. Spans partition the complete input, including controls
and malformed bytes; adjacent offsets meet without gaps.

Call [validate()](../README.md#entry-point-and-validation) before iteration
if you want to reject malformed UTF-8.

## Byte spans

Plain iteration returns `zunic.Span`:

```zig
pub const Span = struct {
    start: ByteOffset,
    end: ByteOffset,
};
```

Each span identifies `bytes[span.start.value..span.end.value]`. The start is
inclusive and the end is exclusive, relative to the view's byte slice.
The iterator returns positions, not a newly allocated string. Neither plain
nor measured iteration normalizes or rewrites the bytes.

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
while (it.next()) |span| {
    const grapheme = bytes[span.start.value..span.end.value];
    std.debug.print("[{s}]: columns={d}\n", .{ grapheme, span.columns });
}
// Output:
// [é]: columns=1
// [界]: columns=2
```

For boundaries alone, omit `.measured()`: the returned `Span` contains only
`start` and `end`.

## Unicode standards

`graphemes()` uses the default extended grapheme cluster rules from
[UAX #29: Unicode Text Segmentation, revision 47](https://www.unicode.org/reports/tr29/tr29-47.html),
for Unicode 17.0.0. Both plain and measured iterators use those boundaries.
Measured columns also use East Asian Width data from
[UAX #11, revision 45](https://www.unicode.org/reports/tr11/tr11-45.html),
with [Zunic's width policy](../width/README.md#display-policy).
UAX #29 does not define terminal column counts.
