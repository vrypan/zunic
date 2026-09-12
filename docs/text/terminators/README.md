# Terminators

[Text view](../README.md) · [Documentation index](../../README.md) · [Implementation](implementation.md)

Use `zunic.text(bytes).terminators().iterator()` to find existing hard line
endings. Each result is the terminator's byte span, with CRLF returned as one
span. Slice the gaps between spans to get line or paragraph content. Use
[wrap()](../wrap/README.md) to fit text to a display-column limit.

The view and iterator borrow the input without copying or allocating. Keep
the bytes alive and unchanged while using them. Opening either does not
scan; `next()` searches for the next terminator and `count()` scans for all
of them. Neither operation validates UTF-8. Call
[validate()](../README.md#entry-point-and-validation) first if required.

## API

```zig
pub fn terminators(self: Text) Terminators;

// Terminators
pub fn count(self: Terminators) usize;
pub fn iterator(self: Terminators) TerminatorIterator;

// TerminatorIterator
pub fn next(self: *TerminatorIterator) ?Span;
```

Each `Span` identifies `bytes[span.start.value..span.end.value]`, with an
inclusive start and exclusive end relative to the view’s bytes. CRLF is one
two-byte span. The recognized characters are:

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
var it = zunic.text(bytes).terminators().iterator();
var start: usize = 0;
while (it.next()) |term| {
    std.debug.print("{s}\n", .{bytes[start..term.start.value]});
    start = term.end.value;
}
std.debug.print("{s}\n", .{bytes[start..]});
// Output:
// one
// two
// three
```

Consecutive terminators produce empty gaps. A trailing terminator leaves an
empty final gap; your application decides whether to expose that as a paragraph.
This differs from [wrap](../wrap/README.md), which omits a synthetic trailing
empty line.

## Unicode standards

`terminators()`, `count()`, and the iterator recognize the hard-break characters
in Unicode 17.0.0
[UAX #14: Unicode Line Breaking Algorithm, revision 55](https://www.unicode.org/reports/tr14/tr14-55.html):
the `BK`, `CR`, `LF`, and `NL` classes, with CRLF treated as one terminator.
This is only hard-terminator detection, not the full line-breaking algorithm.
It reports neither soft break opportunities nor a synthetic end-of-text break.
