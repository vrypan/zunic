# Codepoint iteration

[Text view](../README.md) · [Codepoint properties](../../codepoint/README.md) · [Implementation](implementation.md)

Use `zunic.text(bytes).codepoints().iterator()` to read one codepoint at a
time from a UTF-8 byte string. Each result is a `CodepointView`: pass its
`.value` to code that accepts a `u21`, or use its
[property methods](../../codepoint/README.md).

Use this iterator when your parser or text-processing loop works on individual
codepoints. For slicing or cursor movement that keeps combining sequences
together, use [grapheme iteration](../graphemes/README.md).

Opening the view and iterator does not validate, copy, or allocate. They
borrow the original bytes; keep those bytes alive and unchanged while using
them. Decoding happens as you call `next()`.

## API

```zig
pub fn codepoints(self: Text) Codepoints;

// Codepoints
pub fn iterator(self: Codepoints) CodepointIterator;

// CodepointIterator
pub fn next(self: *CodepointIterator) ?CodepointView;
```

The view and iterator are available as `zunic.Codepoints` and
`zunic.CodepointIterator`. `next()` returns one decoded value, or `null` on
exhaustion or malformed input. Empty input yields no values and no error.
Returned values can be retained independently of the iterator and input bytes.

## Example

```zig
const bytes = "A😀";
var it = zunic.text(bytes).codepoints().iterator();
while (it.next()) |point| {
    std.debug.print("U+{X}\n", .{point.value});
}
if (it.err) |err| {
    std.debug.print("{s} at byte {d}\n", .{ @tagName(err), it.offset });
}
// Output:
// U+41
// U+1F600
```

## Malformed input

After `next()` returns `null`, inspect the iterator's `err` field to
separate normal exhaustion from a decoding failure:

| Result | `err` | `offset` |
| --- | --- | --- |
| End of input | `null` | Input byte length |
| Malformed UTF-8 | `.invalid_utf8` | Start of the undecodable sequence |

`err` has type `?zunic.DecodeError`; its only current error value is
`.invalid_utf8`. Iteration stops before the malformed sequence, without
skipping bytes or substituting a replacement character. Later calls return
`null` and preserve the error and offset.

```zig
var it = zunic.text("A\xffB").codepoints().iterator();
while (it.next()) |point| {
    std.debug.print("U+{X}\n", .{point.value});
}
if (it.err) |err| {
    std.debug.print("{s} at byte {d}\n", .{ @tagName(err), it.offset });
}
// Output:
// U+41
// invalid_utf8 at byte 1
```

Ignoring `err` still stops the loop at malformed input; `B` is never returned.
Stopping the loop early leaves the remaining bytes unchecked, even if `err`
is null.

Call [validate()](../README.md#entry-point-and-validation) first if you want
to reject malformed input before processing any values. That adds a separate
scan and does not change how the iterator works.

## Byte positions

The iterator's `offset: usize` starts at zero. After a successful `next()`,
it points immediately after the decoded sequence. Save it before the call
when you also need the starting position:

```zig
const bytes = "A😀";
var it = zunic.text(bytes).codepoints().iterator();
while (true) {
    const start = it.offset;
    const point = it.next() orelse break;
    const encoded = bytes[start..it.offset];
    std.debug.print("U+{X}: bytes[{d}..{d}] = {s}\n", .{
        point.value, start, it.offset, encoded,
    });
}
// Output:
// U+41: bytes[0..1] = A
// U+1F600: bytes[1..5] = 😀
```

The start is inclusive and the end is exclusive. Offsets index the view's
bytes: after trimming or slicing, they are relative to the smaller slice,
not the original input. This example uses valid input; check `err` after the
loop when decoding may fail.

## Checkpoints and repeated traversal

Copy an iterator to save your place before speculative parsing. The copy
retains its own position and error state; advancing one does not advance
the other. Assign the saved copy back to resume from that checkpoint.

Call `.iterator()` again on the `Codepoints` view to start a new traversal
from the beginning. Both approaches borrow the same input without copying it.
