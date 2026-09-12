# How trimming scans the edges

[API](README.md) · [Source](../../../src/text/trim.zig)

Both scans are scalar, in `src/text/trim.zig`, behind the three `Text` methods
in `src/text/text.zig`. `Text`'s representation is unchanged: a trimmed view is the
same struct over a narrower slice.

## Only the encoding module

The helpers depend on the tolerant UTF-8 decoder and nothing else. The grapheme,
word, width, normalization, and line-break engines answer other questions, and
none of them is needed to decide membership in a 25-code-point set.

The shared fused `Record` carries grapheme, width, and line-break facts; it has
no `White_Space` bit, and adding one would enlarge a table that costs the
library everywhere, for a property with 25 members. A `switch` over 11 ranges
compiles to a handful of comparisons and stays entirely in the instruction
stream. The property is also *not* derivable from data already in the record:
U+00A0 and U+202F are `White_Space` and non-breaking, U+200B is breaking and
zero-width but not `White_Space`.

For the same reason the helpers do not use `decoded_token.at`, which resolves a record
the trim scan would then discard.

## The ASCII shortcut

A byte below `0x80` is answered without decoding: `U+0020`, or `U+0009`
through `U+000D`. Every other ASCII byte ends the scan immediately. Ordinary
text hits this path on its first byte at both ends.

## Forward, from the start

The start scan reads a byte, takes the ASCII answer if it can, and otherwise
steps one scalar with the strict decoder. A null code point — a malformed
sequence — ends the scan at that byte, so the malformed bytes are retained.

## Backward, from the end, with a bounded search

Reading UTF-8 backwards cannot be done by walking over continuation bytes: a
run of them may be the tail of a truncated or overlong sequence, and stopping
at the first byte that looks like a lead can decode a *suffix* of a malformed
scalar as if it were a scalar of its own.

The end scan therefore takes candidate starts two, three, and four bytes back
from the current end, decodes each one forward, and accepts a candidate only
when the decode succeeds *and* consumes exactly the bytes between the candidate
and the current end. A truncated sequence fails the length check; an overlong
or surrogate encoding fails the decode. Four bytes bounds the whole search,
because no UTF-8 sequence is longer.

At most one candidate can succeed, so the order does not matter: a two-byte
match needs `C2..DF` at `end-2`, and the three- and four-byte matches need a
continuation byte there.

The suffix hazard cannot arise for a well-formed input either: every scalar in
the set has lead byte `C2`, `E1`, `E2`, or `E3`, and none of those is a
continuation byte, so no whitespace encoding is a suffix of a longer valid
sequence. The length check is what makes that hold for malformed input too.

Every member of the set fits in at most three UTF-8 bytes, so the four-byte
candidate can never match whitespace; it exists so that a valid four-byte
scalar at the end is recognized as non-whitespace by a real decode rather than
by exhausting the search.

## Concatenated encodings are not a byte set

`std.mem.trim(u8, bytes, " \t\u{00a0}")` is wrong for this job and is never
used: it trims individual *bytes*, so it would strip `C2` and `A0` wherever
they appear and can cut a multi-byte scalar in half.

## Cost

Runtime is proportional to the whitespace removed plus a bounded look at the
first retained scalar at each scanned edge, with constant storage. An
already-trimmed input costs one byte test per scanned end whatever its length;
nothing between the edges is read. `trim()` runs the start scan first and skips
the end scan entirely when nothing remains.

The implementation is deliberately scalar and short. Vector scanning would only
pay on long whitespace runs, which are not the common case; it stays out until
a measurement asks for it. The benchmark harness carries `trim`, `trim_start`,
and `trim_end` rows that consume only the retained slice's relative start and
length, so the edge-only cost is visible and a full-input scan would show up as
size-dependent timing on the unchanged-input cases.

## Tests

[src/text/trim_test.zig](../../../src/text/trim_test.zig) tests the internal text and codepoint modules directly. It
carries its own transcription of the `White_Space` ranges from `PropList.txt`
and sweeps every scalar in Unicode against it, so a predicate that gains or
loses a code point fails there rather than in a sampled case. No host-language
`isspace` or default trim is used as an oracle; their definitions and Unicode
versions differ from this one.
