# Wrap

[Text view](../README.md) · [Documentation index](../../README.md) · [Implementation](implementation.md)

## Unicode standards

`wrap()` combines three sources, using Unicode 16.0.0 data:

- [UAX #14: Unicode Line Breaking Algorithm, revision 53](https://www.unicode.org/reports/tr14/tr14-53.html) supplies line-break opportunities, subject to the [known limitation](implementation.md#known-limitation).
- [UAX #29: Unicode Text Segmentation, revision 45](https://www.unicode.org/reports/tr29/tr29-45.html) supplies extended grapheme boundaries so clusters stay intact.
- [UAX #11: East Asian Width, revision 43](https://www.unicode.org/reports/tr11/tr11-43.html) supplies width properties used by [Zunic's column policy](../width/README.md#display-policy).

Choosing a fitting opportunity and handling overflow are Zunic's layout policy.
UAX #14 identifies opportunities; it does not choose display lines for a given width.
`count()` and the iterator use the same wrapping rules.

## API

```zig
pub fn wrap(self: Text, options: WrapOptions) error{InvalidWidth}!Wrapped;

pub const Overflow = enum { allow, grapheme };
pub const WrapOptions = struct {
    max_columns: usize,
    overflow: Overflow = .grapheme,
};

// Wrapped { bytes: []const u8, options: WrapOptions }
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
It does not balance line lengths, hyphenate words, trim spaces, or allocate
strings. A `Line` describes `bytes[start.value..end.value]`; `columns.value`
is that line's measured width.

`wrap()` returns `InvalidWidth` when `max_columns` is zero, without scanning
the input. Otherwise it returns a reusable view. `count()` traverses all its
lines; it does not consume an existing iterator or cache a count. `next()`
returns `null` at exhaustion. `WrappedIterator` is the returned type from
`text.zig`, not a named export on `zunic`; let Zig infer it.

Use `Text.wrap()` to construct the view. If a `Wrapped` is constructed by hand
with a zero width, its iterator clamps the width to one; `Text.wrap()` itself
continues to reject zero with `InvalidWidth`.

## Overflow and hard breaks

| Option | When no legal break fits |
| --- | --- |
| `.grapheme` (default) | Split at a grapheme boundary. A single cluster wider than the limit stays intact and can exceed it. |
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

## Example

```zig
const bytes = "one two";
const wrapped = try zunic.text(bytes).wrap(.{ .max_columns = 4 });
try std.testing.expectEqual(@as(usize, 2), wrapped.count());
var it = wrapped.iterator();
const first = it.next().?;
try std.testing.expectEqualStrings("one ", bytes[first.start.value..first.end.value]);
try std.testing.expectEqual(@as(usize, 4), first.columns.value);
const second = it.next().?;
try std.testing.expectEqualStrings("two", bytes[second.start.value..second.end.value]);
try std.testing.expect(it.next() == null);

const wide = try zunic.text("abcdef").wrap(.{ .max_columns = 3, .overflow = .allow });
try std.testing.expectEqual(@as(usize, 1), wide.count());
```

## Limits

The line-break rules use Unicode 16 data. They do not include dictionary-based
breaking for scripts that need it. The current line-break engine also has a
known combining-mark issue described on the [implementation page](implementation.md#known-limitation).
ANSI escapes are ordinary input bytes, so strip them before wrapping styled text.

You can stop iteration after a few lines. This avoids producing all remaining
lines, but the first call can scan the whole input to select an ASCII shortcut.
