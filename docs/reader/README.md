# Reader view

[Documentation index](../README.md) · [Codepoint iteration](codepoints.md) ·
[Incremental graphemes](graphemes.md)

Use `zunic.reader(input)` when UTF-8 arrives through a buffered
`*std.Io.Reader`. Construction stores only the pointer and performs no I/O,
allocation, validation, or Unicode property lookup. The caller owns the Reader
and its buffer for the entire traversal.

```zig
pub fn reader(input: *std.Io.Reader) Reader;
```

The Reader view provides strict [codepoint iteration](codepoints.md) and
[incremental grapheme updates](graphemes.md). It does not provide streaming
normalization, casing, or width APIs.

This is a single-pass view. Copies and iterators share the underlying Reader's
cursor, so use only one active consumer unless you deliberately coordinate all
access. Zunic never closes or owns the source.
