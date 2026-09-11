# Normalization implementation decisions

[API](README.md) · [Source](../../../src/normalization/normalization.zig)

## Buffer one combining run

Normalization must see the following marks before it can finish a starter:
marks may need reordering or may compose with it. The iterator keeps one run
in an inline buffer and emits it only when it is ready. A separate held entry
keeps the starter that closes the current run until that run has been returned.

This gives bounded memory use without an allocator. The cost is an explicit
`SequenceTooLong` error on runs that exceed the configured limit. The limit is
counted after decomposition -- compatibility-aware for NFKC/NFKD, canonical
only for NFC/NFD -- independently of composition, so neither composing form
can hide an excessive run by combining it into fewer output characters.

The run's marks are ordered with a stable insertion sort. Equal combining
classes keep their original order. The sort can do quadratic work within a
run, but run size is bounded by the build setting. With that setting fixed,
total work remains linear in input length. Raising the limit increases both
the memory requirement and worst-case sorting work per run.

## Avoid searches that cannot succeed

One packed property lookup says whether a character decomposes canonically,
whether it decomposes under compatibility, its combining class, its NFC and
NFKC quick-check values, and whether it can take part in composition -- all
sixteen bits used, no padding left. Most characters do neither kind of
decomposition, so they need no search through either mapping table. Two bits
rule out impossible composition pairs before a pair-table search.

Canonical and compatibility mappings live in separate generated tables, not
because the questions differ in kind but because their shapes do: a canonical
mapping is at most two scalars immediate, and packs a one-bit pair flag and a
12-bit offset into decomposition data shared with composition; a compatibility
mapping runs up to 18 scalars immediate (U+FDFA), which does not fit that
scheme, and would cost every canonical lookup a wider field it never uses.
The compatibility table instead stores only an offset per entry and derives
each one's length from the next entry's offset -- entries are sorted by code
point with their data laid out in that same order and no gaps, so no length
field is needed at all. A canonical-only code point is absent from the
compatibility table entirely; NFKD's decomposition falls through to the same
canonical table NFD uses.

NFKC_QC is a third stored property, not derived from NFC_QC: a code point can
quick-check `yes` under NFC while quick-checking `no` under NFKC -- U+0385
GREEK DIALYTIKA TONOS decomposes canonically to U+00A8 U+0301, and U+00A8
DIAERESIS has its own compatibility mapping to U+0020 U+0308, so the full NFKD
of U+0385 replaces the diaeresis symbol with a plain space and cannot recompose
back to it, even though NFC leaves U+0385 untouched. NFKD_QC needs no separate
property: it is `no` exactly when a code point decomposes canonically or
compatibly, verified against the real property rather than assumed, since the
NFKC_QC exception shows this kind of derivation is not automatically safe.

Hangul decomposition and composition use arithmetic instead of stored mappings,
identically for every form.

### A second scratch buffer for compatibility mappings

A four-entry scratch array holds one fully decomposed scalar under NFC/NFD;
four is the maximum checked against the pinned Unicode data by the property
tests, unchanged by this. NFKC/NFKD need up to `properties.max_compat_expansion`
entries (18, also checked against the pinned data, at U+FDFA) for the same
purpose, so their iterator instantiates a larger scratch array -- 248 bytes
against NFC/NFD's 192 -- while NFC/NFD's own instantiation is untouched, byte
for byte. This is a compile-time choice, resolved per `Form` by
`Iterator(comptime form: Form)`, not a runtime branch or a single shared
worst-case buffer every form pays for.

The combining-run buffer this scratch space feeds is a separate, unrelated
bound: it limits how many non-starters can accumulate *across* input scalars,
while scratch bounds how many entries *one* scalar's decomposition can produce.
A compatibility mapping that itself contains several starters -- U+FDFA's
eighteen scalars are eighteen separate Arabic letters and spaces, no combining
marks among them -- streams through the existing per-entry emission one entry
at a time, exactly as a run of ordinary characters would; nothing about a wide
scratch buffer bypasses the run limit or needs it raised.

NFC composition tracks the last retained combining class to decide whether
an intervening mark blocks a pair. It also handles composition across starters,
including Hangul, instead of assuming every new starter must end output. NFKC
reuses this exactly: composition never rebuilds a compatibility mapping (a
ligature never reappears once decomposed), but a *canonical* pair inside an
NFKD expansion composes normally -- U+01C4's compatibility mapping is "D" +
U+017D, and U+017D's own canonical decomposition is "Z" + a combining caron,
so NFKC(U+01C4) is "D" + U+017D again, not the three-scalar NFKD form and not
the original ligature-shaped U+01C4.

## Answer common queries without writing normalized text

Equality advances two iterators together and compares their scalars --
`.canonical` uses NFD, `.compatibility` uses NFKD. It needs no complete output
buffers and can stop at the first difference. Strict UTF-8 handling prevents
different malformed byte strings from comparing equal merely because both
became replacement characters.

`isNormalized` uses Unicode quick-check properties and combining order. A
decomposing form (NFD, NFKD) can reject a decomposing character immediately --
NFKD also rejecting one that only decomposes under compatibility. A composing
form (NFC, NFKC) has a third quick-check answer, `Maybe`: the preceding
context decides whether composition changes it. NFKC reads `NFKC_QC`, a
separate stored property from `NFC_QC`, not derived from it (see
[Avoid searches that cannot succeed](#avoid-searches-that-cannot-succeed)).

When the current character has no decomposition and earlier decomposed marks
cannot reorder around it, a local composition check settles that `Maybe`.
The check retains the highest decomposed combining class, including marks
hidden in a precomposed starter. Only marks retained after the written starter
block composition; marks already absorbed into it do not. NFKC tracks this
context using compatibility decomposition.
If reordering might matter, or the current character itself decomposes, the
code normalizes and compares the relevant prefix using the real algorithm,
in the same form. This saves work on common already-normalized input while
retaining the full check where it is needed.

`isNormalizedQuick()` exposes the three-valued check without settling Maybe.
It checks written combining order and per-character quick-check properties,
using constant state. It scans the complete slice, reports malformed UTF-8
even after finding No, and does not enforce the normalization buffer limit.
It does not invoke the normalization iterator or change `isNormalized()`.

## Bound output space separately

The UTF-8 capacity bound is generated from pinned data, and differs by kind
rather than by form within a kind: NFC and NFD share one factor (3x, measured
at U+1D160 for NFC and U+0390 for NFD), and NFKC and NFKD share another (11x,
measured at U+FDFA) -- NFC and NFKC do not get their own smaller bounds despite
composing, because composition is separately proven byte-nonincreasing
(verified for every eligible pair during generation), so composing after
decomposition can only shrink or hold the byte count decomposition alone
already bounds. Multiplication is checked for overflow. The output bound says
nothing about UTF-8 validity or run length.

[Normalization tests](../../../src/normalization_test.zig) cover Unicode fixtures,
ordering, composition, malformed input, buffer limits, partial results, and
query shortcuts, for all four forms. Property-generator tests check the
scratch-size and expansion bounds against the pinned data, canonical and
compatibility alike, and the conformance suite
(`zig build test-conformance`) checks NFKC and NFKD against all 20,034 cases
of the pinned `NormalizationTest-17.0.0.txt`, the same fixture NFC and NFD
are checked against.
