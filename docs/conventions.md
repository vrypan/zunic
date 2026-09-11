# Shared API conventions

[Documentation index](README.md)

```zig
pub fn text(bytes: []const u8) Text;
```

`zunic.text(bytes)` constructs a view without scanning, validating, copying, or
allocating. It exposes the borrowed slice as `.bytes`. Keep its storage alive
and unchanged while using a view or iterator. A view does not own or free memory.

Every `.iterator()` call creates independent traversal state at the beginning
of its view. Call `next()` on a mutable iterator until it returns `null`.
Copying an iterator copies its current position and inline state, not its input.
Counting or measuring runs a traversal; results are not cached in the view.

## Byte offsets and columns

```zig
pub const ByteOffset = struct { value: usize };
pub const Column = struct { value: usize };
pub const Span = struct { start: ByteOffset, end: ByteOffset };
```

All spans are half-open: `bytes[span.start.value..span.end.value]`.
Offsets index the input slice of the Text view, even when that slice is itself
a substring. Trimming returns a new Text; its offsets index
the retained slice, starting at zero. They count **bytes**, not scalars, graphemes, or columns.
`Column` deliberately separates display measurements from byte offsets.
Returned spans borrow the input indirectly; they contain no copied text.

## Plain text and malformed input

The text view does not interpret ANSI escape sequences, expand tabs, or emulate a
terminal cursor. Strip styling escapes before measuring or wrapping styled
text. Width is a fixed terminal-cell policy, not font shaping or terminal
capability detection. CR and LF have zero width; `width()` sums the text's
columns rather than returning the widest physical line.

Grapheme, word, width, wrap, and trim operations tolerate malformed UTF-8,
advancing one byte at a time on decoding errors. They retain original byte
offsets and do not rewrite the input. A span can therefore contain malformed
bytes.
Terminators scan for exact byte sequences and are not a UTF-8 validator. The
trim methods stop at a malformed sequence at the edge they scan and retain it.

Call `try text.validate()` when an operation should require valid UTF-8. It
checks the complete slice directly, without grapheme iteration or Unicode
property lookups:

```zig
const text = zunic.text(input);
try text.validate();
```

Validation returns `InvalidUtf8` for malformed input and otherwise returns
nothing. It does not change the view or the behavior of later operations.

Normalization is deliberately different: it returns `InvalidUtf8` for malformed
input and `SequenceTooLong` when its configured combining-run limit is reached.
See [normalization error semantics](text/normalization/README.md#errors-and-partial-results).

## Laziness

Constructing grapheme, word, terminator, wrap, and normalization views does no
input traversal. `wrap` checks the width option immediately. Creating a word
iterator reads its first character to initialize its state. Further work
happens on `next`, `count`, `width`, or a normalization query. The trim methods
are the exception among `Text` methods that return a view: each one scans its
edges when called and returns the narrowed slice.

Lazy does not mean zero lookahead: grapheme boundaries need a following token,
word rules may look past ignored marks, and normalization buffers a combining
run. Wrapping and word iteration can inspect the entire byte slice on their
first `next()` to select an ASCII fast path, even if the caller only requests
one result.
