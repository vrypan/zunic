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
