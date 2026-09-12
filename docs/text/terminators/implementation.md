# Why terminators scan bytes

[API](README.md) · [Source](../../../src/text/text.zig)

Hard terminators are a fixed, small set. The iterator recognizes their exact
UTF-8 encodings directly, avoiding Unicode property lookups and grapheme
segmentation for a question that does not need them.

This is sound for valid UTF-8: ASCII terminator bytes cannot occur inside a
multi-byte encoding because continuation bytes are at least `0x80`. NEL and
the two Unicode separators require a full matching sequence, including length
checks. CR followed immediately by LF is consumed as one span.

Grapheme rules break on both sides of these control characters, with CRLF as
the explicit exception that stays together. A full grapheme iterator would
therefore find the same terminator extents. The shortcut preserves this result
without doing the unrelated work.

On malformed input, the scanner advances through bytes and still recognizes
any complete terminator sequence it encounters. It deliberately offers no
whole-input validation guarantee.

Traversal is linear with constant state: the borrowed slice and a current byte
position. `count()` is a fresh traversal, not stored metadata. See
[root tests](../../../src/root_test.zig) for terminator and paragraph edge cases.
