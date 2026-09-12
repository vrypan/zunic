# Wrap

[Text view](../README.md) · [Documentation index](../../README.md) · [Implementation](implementation.md)

Use `try zunic.text(bytes).wrap(options)` to split UTF-8 text into display
lines under a column limit. **Wrapping works with whole
[grapheme clusters](../graphemes/README.md)**: a letter with combining marks,
a flag, or an emoji sequence stays together on one line. The limit counts
display columns, not bytes, codepoints, or graphemes.

Call `.iterator()` on the result to read each line's byte span and width.
For existing hard line endings, use
[terminators()](../terminators/README.md).

The view and iterator borrow the original bytes without copying or allocating
line strings. Keep the input alive and unchanged while using them. Opening
the view checks the width option but does not scan or validate the text;
wrapping happens during iteration. Call
[validate()](../README.md#entry-point-and-validation) first if malformed
UTF-8 should be rejected.

## API

```zig
pub fn wrap(self: Text, options: WrapOptions) error{InvalidWidth}!Wrapped;

pub const Overflow = enum { allow, grapheme };
pub const WrapOptions = struct {
    max_columns: usize,
    overflow: Overflow = .grapheme,
};

// Wrapped
pub fn count(self: Wrapped) usize;
pub fn iterator(self: Wrapped) WrappedIterator;

// WrappedIterator
pub fn next(self: *WrappedIterator) ?Line;

pub const Line = struct {
    start: ByteOffset,
    end: ByteOffset,
    columns: Column,
};
```

Wraps plain text into display lines using terminal columns and Unicode line
break opportunities. It chooses the last fitting opportunity before overflow.
Each line contains whole grapheme clusters, measured using Zunic's
[display-width policy](../width/README.md#display-policy).

A grapheme measures
at most two columns. With the default `.grapheme` overflow mode, an individual
grapheme can therefore exceed the limit only when `max_columns == 1`: a
two-column grapheme stays intact. At `max_columns >= 2`, every individual
grapheme fits. The `.allow` mode can still exceed the limit by keeping a
longer unbreakable run together.

`wrap()` does not balance line lengths, hyphenate words, trim spaces, or allocate
strings. A `Line` describes `bytes[start.value..end.value]`; `columns.value`
is that line's measured width. Offsets are relative to the view’s bytes,
with an inclusive start and exclusive end.

`wrap()` returns `InvalidWidth` when `max_columns` is zero, without scanning
the input. Otherwise it returns a reusable view. `count()` traverses all its
lines; it does not consume an existing iterator or cache a count. `next()`
returns `null` at exhaustion. Let Zig infer the iterator type.

## Example

```zig
const bytes = "one two";
const wrapped = try zunic.text(bytes).wrap(.{ .max_columns = 4 });
var it = wrapped.iterator();
while (it.next()) |line| {
    std.debug.print("[{s}]: columns={d}\n", .{
        bytes[line.start.value..line.end.value], line.columns.value,
    });
}
// Output:
// [one ]: columns=4
// [two]: columns=3
```

## Example: keep multi-codepoint graphemes together

Here `e\u{0301}` contains a letter and a combining accent, and `🇬🇷` contains
two regional-indicator codepoints. Each sequence is one grapheme. A one-column
limit forces narrow lines, but neither sequence is split:

```zig
const bytes = "e\u{0301}🇬🇷x";
const wrapped = try zunic.text(bytes).wrap(.{ .max_columns = 1 });
var it = wrapped.iterator();
while (it.next()) |line| {
    std.debug.print("[{s}]: bytes={d}, columns={d}\n", .{
        bytes[line.start.value..line.end.value],
        line.end.value - line.start.value,
        line.columns.value,
    });
}
// Output:
// [é]: bytes=3, columns=1
// [🇬🇷]: bytes=8, columns=2
// [x]: bytes=1, columns=1
```

The flag exceeds the one-column limit because preserving its grapheme takes
priority over fitting it into a narrower line.

## Overflow and hard breaks

| Option | When no legal break fits |
| --- | --- |
| `.grapheme` (default) | Split at a grapheme boundary. With `max_columns == 1`, a two-column cluster stays intact and exceeds the limit. |
| `.allow` | Keep the unbreakable run together, even if the line exceeds the limit. A fitting legal break is still preferred. |

Neither mode splits an extended grapheme cluster. Width uses the same policy
as [`width()`](../width/README.md). Malformed bytes are tolerated and preserved
in the returned slices, with no width contribution of their own.

Hard terminators end the current line and are excluded from its slice. CRLF
counts as one terminator. Empty input yields no lines. Leading or consecutive
terminators can yield empty lines; a trailing terminator does not add a final
empty line. For example, `"a\n"` yields `"a"`, and `"\n\n"` yields two empty lines.

Spaces are preserved and count towards the limit, including trailing spaces
before a soft break. The result is not a trimmed list of words.

## Limits

The line-break rules use Unicode 17 data. They do not include dictionary-based
breaking for scripts that need it.
ANSI escapes are ordinary input bytes, so strip them before wrapping styled text.

You can stop iteration after a few lines. This avoids producing all remaining
lines, but the first call can scan the whole input to select an ASCII shortcut.

## Unicode standards

`wrap()` combines three sources, using Unicode 17.0.0 data:

- [UAX #14: Unicode Line Breaking Algorithm, revision 55](https://www.unicode.org/reports/tr14/tr14-55.html) supplies line-break opportunities.
- [UAX #29: Unicode Text Segmentation, revision 47](https://www.unicode.org/reports/tr29/tr29-47.html) supplies extended grapheme boundaries so clusters stay intact.
- [UAX #11: East Asian Width, revision 45](https://www.unicode.org/reports/tr11/tr11-45.html) supplies width properties used by [Zunic's column policy](../width/README.md#display-policy).

Choosing a fitting opportunity and handling overflow are Zunic's layout policy.
UAX #14 identifies opportunities; it does not choose display lines for a given width.
`count()` and the iterator use the same wrapping rules.
