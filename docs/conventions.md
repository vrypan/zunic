# Shared API conventions

[Documentation index](README.md)

```zig
pub fn text(bytes: []const u8) Text;
pub fn validate(self: Text) error{InvalidUtf8}!void;
```

`zunic.text(bytes)` constructs a view without scanning, validating, copying,
or allocating. `Text.bytes` is the borrowed slice. Keep its storage alive and
unchanged while using a view or iterator. A view does not own or free memory.

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
Offsets index the original slice passed to `text`, even when that slice is
itself a substring. They count **bytes**, not scalars, graphemes, or columns.
`Column` deliberately separates display measurements from byte offsets.
Returned spans borrow the input indirectly; they contain no copied text.

## Plain text and malformed input

The text view does not interpret ANSI escape sequences, expand tabs, or emulate a
terminal cursor. Strip styling escapes before measuring or wrapping styled
text. Width is a fixed terminal-cell policy, not font shaping or terminal
capability detection. CR and LF have zero width; `width()` sums the text's
columns rather than returning the widest physical line.

The separate [terminal view](terminal/README.md) currently provides grapheme
iteration that ignores supported CSI/OSC sequences. Its spans still index the
original bytes and exclude recognized escapes. An escape inside a grapheme
returns `EscapeInsideGrapheme` before that grapheme is emitted.
Terminal width and wrapping are not implemented yet.

Grapheme, word, width, and wrap operations tolerate malformed UTF-8, advancing
one byte at a time on decoding errors. They retain original byte offsets and
do not rewrite the input. A span can therefore contain malformed bytes.
Terminators scan for exact byte sequences and are not a UTF-8 validator.

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
See [normalization error semantics](normalization/README.md#errors-and-partial-results).

## Laziness

Constructing grapheme, word, terminator, wrap, and normalization views does no
input traversal. `wrap` checks the width option immediately. Creating a word
iterator reads its first character to initialize its state. Further work happens
on `next`, `count`, `width`, or a normalization query.

Lazy does not mean zero lookahead: grapheme boundaries need a following token,
word rules may look past ignored marks, and normalization buffers a combining
run. Wrapping can inspect the entire byte slice on its first `next()` to
select an ASCII fast path, even if the caller only requests one line.
