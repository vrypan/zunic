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
its own lookup. `grapheme()` and `width()` share the compact grapheme/width
record, while `isEastAsianWide()` reuses the terminal record. Codepoint-only
calls therefore do not retain the wider line-break/layout table. Whitespace uses a small fixed predicate shared with text
trimming. Case folding has an ASCII uppercase fast path followed by indexed
mapping tables, returning an owned buffer of at most three values.

The general-property trie stores precomputed `u16` element offsets in its
middle stage. Combining an offset with the low four codepoint bits selects
the leaf class ID without scaling a page ID at runtime. The index width and
total table size are unchanged.

Primary Script uses a fixed two-stage prefix trie. The high bits index 8,704
precomputed `u16` offsets, and the low seven bits select a `Script` within one
of 255 deduplicated 128-codepoint pages. Its arrays occupy 50,048 bytes and
every in-range lookup performs two dependent reads. Storing offsets avoids
shifting the first lookup result before the second read. On Apple M4 with
Zig 0.17, this reduced Script lookup time by about 8% compared with byte-sized
page IDs, at a cost of 8,704 additional table bytes. Script_Extensions stays in
separate sparse storage so a primary-only caller does not retain it: 176 merged ranges use binary search,
then address 118 deduplicated static sets. The extension arrays occupy 2,003
bytes, for 52,051 bytes when both methods are retained.

Bidirectional classification uses another two-stage prefix table with the same
seven-bit page suffix. Its raw one-byte leaf combines the 23-value Bidi_Class,
mirrored status, and three-value paired-bracket type, so a lookup takes two
dependent reads without a class-record translation. The dense arrays occupy
33,152 bytes. Mirroring glyphs and paired brackets use separate two-stage BMP
tables (4,736 and 3,328 bytes). This preserves independent dead stripping,
unambiguous optional results, and constant-time lookups. The generator asserts
that all Unicode 17 mapping keys and values fit in the BMP; a future Unicode upgrade
must widen these arrays before accepting supplementary mappings.

The three simple case mappings share a two-stage index. One read selects a
leaf offset; another reads the signed delta from the uppercase, lowercase, or
titlecase array. ASCII uses the same lookup. Separate payload arrays allow
unused case operations to stay out of the binary. Keeping this separate from
full case folding preserves the one-codepoint result and distinct semantics.

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
implementing full default Unicode case folding. The first-stage index ends
at the page containing the last C/F mapping, with the bound generated from
the pinned input. Unicode 17 needs 490 `u16` offsets covering codepoints below
`0x1EA00`; higher values retain the identity mapping. The offsets address
6,912 `u16` mapping IDs. These lookup arrays occupy 14,804 bytes, down from
18,176 bytes; the mapping payload is unchanged and excluded from those counts.
On Apple M4 with Zig 0.17, bounded offsets reduced case-fold lookup time by
about 13% across the comparison corpora.

The [text iterator](../../src/text/codepoints.zig) decodes UTF-8 before constructing
each view. Internal segmentation and layout instead use
[decoded tokens](../../src/encoding/decoded_token.zig), which carry byte
positions and already gathered facts for reuse. Those tokens serve text
engines; they are not the public codepoint view.

Run `zig build test-unicode-properties` for independent exhaustive checks of
the generated property tables against their pinned Unicode sources. Run
`zig build test-cp` for compiled property and folding tests, including wider
`u21` fallbacks and the pinned case-folding fixture.
`zig build test-text` and `zig build test-api` cover decoding behavior and
public API integration. Module refactoring previously preserved the optimized
comparison benchmark's machine code; future representation or inlining
changes should be measured rather than assumed to preserve performance.
