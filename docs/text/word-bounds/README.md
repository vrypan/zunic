# Word boundaries

[Text view](../README.md) · [Documentation index](../../README.md) · [Implementation](implementation.md)

## Unicode standards

`wordBounds()` and its iterator use the default word-boundary rules from
[UAX #29: Unicode Text Segmentation, revision 45](https://www.unicode.org/reports/tr29/tr29-45.html),
for Unicode 16.0.0. They do not add dictionary or locale-specific segmentation.
The `is_word` flag is Zunic's convenience flag; UAX #29 defines the boundaries,
not that flag.

## API

```zig
pub fn wordBounds(self: Text) WordBounds;

// WordBounds { bytes: []const u8 }
pub fn iterator(self: WordBounds) WordBoundIterator;

// WordBoundIterator
pub fn next(self: *WordBoundIterator) ?WordBound;

pub const WordBound = struct {
    start: ByteOffset,
    end: ByteOffset,
    is_word: bool,
};
```

Returns the default, locale-independent UAX #29 word segments for Unicode 16.
The segments cover the complete input in order, with no gaps or overlap.
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

Malformed UTF-8 advances one byte and receives the `Other` word class, without
the word-like flag. Boundary rules still apply; a following ignored combining
mark may join that byte. This API is not a UTF-8 validator.

## Example: keep word-like segments

```zig
const bytes = "Hello, world!";
var it = zunic.text(bytes).wordBounds().iterator();
const expected = [_][]const u8{ "Hello", "world" };
var count: usize = 0;
while (it.next()) |segment| {
    if (!segment.is_word) continue;
    try std.testing.expectEqualStrings(expected[count], bytes[segment.start.value..segment.end.value]);
    count += 1;
}
try std.testing.expectEqual(@as(usize, 2), count);
```

There is no separate `words()` method or built-in collection/count method.
Filter `is_word`, count, or store results in the caller as needed.
