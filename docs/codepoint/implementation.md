# Codepoint implementation

[Codepoint API](README.md) · [Source](../../src/cp/cp.zig)

The internal `cp` Zig module owns `CodepointView`, its property result types,
case folding, and the scalar whitespace predicate. Its only named dependency
is `tables`. The public `zunic` module re-exports its constructor as `cp()`;
applications continue to import `zunic`.

`CodepointView` stores `value: u21` in a `packed struct(u32)` with eleven
padding bits. The 32-bit backing avoids a narrow-integer memory round trip
observed with the Zig 0.16 compiler. Construction only stores the value;
there is no allocation, decoding, validation, or cached property record.
This representation choice is internal and does not mean UTF-8 uses four
bytes for every codepoint.

`general()`, `terminal()`, and `grapheme()` obtain their respective packed
table results and bitcast them to the public field layout. Each group has
its own lookup. `width()` and `isEastAsianWide()` delegate to the existing
property accessors. Whitespace uses a small fixed predicate shared with text
trimming. Case folding has an ASCII uppercase fast path followed by indexed
mapping tables, returning an owned buffer of at most three values.

The three simple case mappings share a class-deduplicated trie. Each class
stores signed uppercase, lowercase, and titlecase deltas from the input value;
ASCII letters bypass the table. Keeping this separate from full case folding
preserves the one-codepoint result and the distinct Unicode semantics.

Numeric values use a separate three-stage trie whose class records contain an
exact reduced numerator and denominator. Keeping it separate avoids adding
numeric data to general-property lookups. Normalization's combining class
reuses the normalizer's class trie; immediate decompositions borrow the same
canonical and compatibility mapping arrays used by the normalization engine.
A separate two-stage index selects the mapping kind and array entry in two
dependent reads, without binary searches. Unmapped values, including Hangul
syllables whose decomposition is algorithmic, have a zero index. This index
adds about 28 KiB of table data when `cp().decomposition()` is used; the text
normalization engine retains its existing lookups.

The folding tables use the C (common) and F (full) mappings from the pinned
`CaseFolding.txt`. They exclude the S (simple) and T (Turkic) alternatives,
implementing full default Unicode case folding.

The [text iterator](../../src/text/text.zig) decodes UTF-8 before constructing
each view. Internal segmentation and layout instead use
[decoded tokens](../../src/encoding/decoded_token.zig), which carry byte
positions and already gathered facts for reuse. Those tokens serve text
engines; they are not the public codepoint view.

Run `zig build test-cp` for property and folding tests, including comparisons
across the complete `u21` domain and the pinned case-folding fixture.
`zig build test-text` and `zig build test-api` cover decoding behavior and
public API integration. Module refactoring previously preserved the optimized
comparison benchmark's machine code; future representation or inlining
changes should be measured rather than assumed to preserve performance.
