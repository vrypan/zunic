# Shared API conventions

[Documentation index](README.md)

Use these conventions when working with Zunic views, iterators, and results.
Operation pages describe their specific return types and error behavior.

## Ownership and lifetimes

`zunic.cp(value)` holds a numeric value. `zunic.text(bytes)` borrows the input
slice and exposes it as `.bytes`, without scanning, validating, copying, or
allocating. Keep that storage alive and unchanged while using a Text view or
its iterators. A view does not own or free memory.

Results that contain byte offsets refer to the original input; they contain
no copied text. Results that own inline storage, such as `CaseFold`, have their
own lifetime rules described on the relevant API page.

## Iteration and copying

Every `.iterator()` call creates independent traversal state at the beginning
of its view. Call `next()` on a mutable iterator until it returns `null`.
[Normalization](text/normalization/README.md) returns an iterator directly,
and its `next()` also returns errors.

Copying an iterator copies its current position and inline state, not its
input. The copies can advance independently over the same borrowed bytes.
Counting or measuring performs work on each call; results are not cached in
the view.

## Byte offsets and columns

```zig
pub const ByteOffset = struct { value: usize };
pub const Column = struct { value: usize };
pub const Span = struct { start: ByteOffset, end: ByteOffset };
```

All spans are half-open: `bytes[span.start.value..span.end.value]`.
Offsets index the input slice of the Text view, even when that slice is itself
a substring. Trimming returns a new Text; its offsets index the retained
slice, starting at zero. They count **bytes**, not codepoints, graphemes, or
columns. `Column` separates display measurements from byte offsets.

## Plain text and malformed input

Text operations do not interpret ANSI escape sequences, expand tabs, or
emulate a terminal cursor. Width follows a fixed display-cell policy; it does
not measure font shaping or detect terminal capabilities. See the
[display-width policy](text/width/README.md#display-policy).

Creating a Text view does not validate UTF-8. Use
[`validate()`](text/README.md#entry-point-and-validation) to check it in
advance. This is an additional scan, and its result is not cached.

| Operation | Malformed UTF-8 behavior |
| --- | --- |
| Graphemes, word boundaries, width, wrap | Tolerate malformed bytes, retaining original byte offsets without rewriting the input |
| [Trim](text/trim/README.md) | Stops at a malformed sequence at the edge being scanned and retains it |
| [Terminators](text/terminators/README.md) | Scans for exact byte sequences without validating UTF-8 |
| [Codepoints](text/codepoints/README.md#malformed-input) | Stops and records the decoding error and byte offset on the iterator |
| [Normalization](text/normalization/README.md#errors-and-partial-results) | Reports `InvalidUtf8` when encountered |

A returned span can contain malformed bytes. Normalization can also report
`SequenceTooLong` when its configured
[combining-run limit](text/normalization/README.md#combining-run-limit) is exceeded.

## When work happens

Opening a Text view does not scan the input. Iterators process text as they
advance, but may read ahead or scan for an ASCII fast path before returning
the first result. Requesting one result does not guarantee that only that
result's bytes will be inspected.

Trimming scans the relevant edges when called. Validation, ASCII checks,
counting, width measurement, and normalization queries perform their work
when called. See each operation's implementation page for its scanning and
buffering strategy.
