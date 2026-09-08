# Terminators

[Documentation index](../README.md) · [Implementation](implementation.md)

## Unicode standards

`terminators()`, `count()`, and the iterator recognize the hard-break characters
in Unicode 16.0.0
[UAX #14: Unicode Line Breaking Algorithm, revision 53](https://www.unicode.org/reports/tr14/tr14-53.html):
the `BK`, `CR`, `LF`, and `NL` classes, with CRLF treated as one terminator.
This is only hard-terminator detection, not the full line-breaking algorithm.
It reports neither soft break opportunities nor a synthetic end-of-text break.

## API

```zig
pub fn terminators(self: Text) Terminators;

// Terminators { bytes: []const u8 }
pub fn count(self: Terminators) usize;
pub fn iterator(self: Terminators) TerminatorIterator;

// TerminatorIterator
pub fn next(self: *TerminatorIterator) ?Span;
```

Returns the byte extent of each hard line terminator physically present in the
input. CRLF is one two-byte span. The recognized characters are:

| Character | Code point | UTF-8 bytes |
| --- | --- | --- |
| Line feed (LF) | U+000A | `0A` |
| Vertical tab (VT) | U+000B | `0B` |
| Form feed (FF) | U+000C | `0C` |
| Carriage return (CR) | U+000D | `0D` |
| Next line (NEL) | U+0085 | `C2 85` |
| Line separator | U+2028 | `E2 80 A8` |
| Paragraph separator | U+2029 | `E2 80 A9` |

`count()` scans for terminators; it does not count display lines or paragraphs.
`next()` returns `null` at exhaustion. Empty input and input without terminators
yield no spans. End of text does not create a synthetic terminator. Truncated
multi-byte sequences do not match; the operation otherwise does not validate
UTF-8.

## Example: iterate paragraph gaps

```zig
const bytes = "one\r\ntwo\u{2028}three";
const terms = zunic.text(bytes).terminators();
try std.testing.expectEqual(@as(usize, 2), terms.count());
var it = terms.iterator();
var start: usize = 0;
const expected = [_][]const u8{ "one", "two" };
var index: usize = 0;
while (it.next()) |term| {
    try std.testing.expectEqualStrings(expected[index], bytes[start..term.start.value]);
    start = term.end.value;
    index += 1;
}
try std.testing.expectEqualStrings("three", bytes[start..]);
```

Consecutive terminators produce empty gaps. A trailing terminator leaves an
empty final gap; your application decides whether to expose that as a paragraph.
This differs from [wrap](../wrap/README.md), which omits a synthetic trailing
empty line.
