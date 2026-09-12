# Word boundaries

[Text view](../README.md) · [Documentation index](../../README.md) · [Implementation](implementation.md)

Use `zunic.text(bytes).wordBounds().iterator()` to partition UTF-8 text into
word segments and separators. Each result is a byte span; filter on `is_word`
when you want only word-like segments. The boundaries follow default Unicode
rules, without dictionary or language-specific segmentation.

The view and iterator borrow the original bytes without copying or allocating.
Keep those bytes alive and unchanged while using them. This operation
tolerates malformed UTF-8; call
[validate()](../README.md#entry-point-and-validation) first if you need to
reject it. See below for when iteration scans and what `is_word` means.

## API

```zig
pub fn wordBounds(self: Text) WordBounds;

// WordBounds
pub fn iterator(self: WordBounds) WordBoundIterator;

// WordBoundIterator
pub fn next(self: *WordBoundIterator) ?WordBound;

pub const WordBound = struct {
    start: ByteOffset,
    end: ByteOffset,
    is_word: bool,
};
```

Returns the default, locale-independent UAX #29 word segments for Unicode 17.
Slice each result as `bytes[segment.start.value..segment.end.value]`. The
start is inclusive and the end is exclusive, relative to the view’s bytes.
Segments cover the complete input in order, with no gaps or overlap.
Punctuation and whitespace are returned too. Adjacent non-word segments are
not merged just because they share `is_word = false`.

`next()` returns `null` at exhaustion. Empty input yields no segments. The
view and iterator allocate nothing and do not normalize or copy text.
Creating the view scans nothing; creating its iterator reads the first character.
The first `next()` may inspect the whole input to select the ASCII fast path,
even if you only request one segment.

## What `is_word` means

`is_word` is true when at least one character in the segment has the Unicode
`Alphabetic` property or a numeric general category (`Nd`, `Nl`, or `No`).
It is a convenience flag, not part of the boundary rule and not proof that
the segment is a linguistic word. Some combining marks and numeric symbols
qualify; punctuation and ordinary spaces do not.

Default boundaries do not provide dictionary segmentation for Thai, Lao,
Khmer, Myanmar, Chinese, or Japanese. Applications needing linguistic words
in those scripts need additional language-specific processing.

Malformed bytes remain in the spans; iteration does not stop with a decoding
error. They are not inherently word-like, but can share a segment with
following combining marks.

## Example: distinguish words and separators

```zig
const bytes = "Hello, world!";
var it = zunic.text(bytes).wordBounds().iterator();
while (it.next()) |segment| {
    const note: []const u8 = if (segment.is_word) "" else " (non-word)";
    std.debug.print("[{s}]{s}\n", .{
        bytes[segment.start.value..segment.end.value], note,
    });
}
// Output:
// [Hello]
// [,] (non-word)
// [ ] (non-word)
// [world]
// [!] (non-word)
```

There is no separate `words()` method or built-in collection/count method.
Filter `is_word`, count, or store results in the caller as needed.

## Unicode standards

`wordBounds()` and its iterator use the default word-boundary rules from
[UAX #29: Unicode Text Segmentation, revision 47](https://www.unicode.org/reports/tr29/tr29-47.html),
for Unicode 17.0.0. They do not add dictionary or locale-specific segmentation.
The `is_word` flag is Zunic's convenience flag; UAX #29 defines the boundaries,
not that flag.
