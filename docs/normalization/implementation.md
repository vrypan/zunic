# Normalization implementation decisions

[API](README.md) · [Source](../../src/normalization.zig)

## Buffer one combining run

Normalization must see the following marks before it can finish a starter:
marks may need reordering or may compose with it. The iterator keeps one run
in an inline buffer and emits it only when it is ready. A separate held entry
keeps the starter that closes the current run until that run has been returned.

This gives bounded memory use without an allocator. The cost is an explicit
`SequenceTooLong` error on runs that exceed the configured limit. The limit is
counted after decomposition, independently of composition, so NFC cannot hide
an excessive run by combining it into fewer output characters.

The run's marks are ordered with a stable insertion sort. Equal combining
classes keep their original order. The sort can do quadratic work within a
run, but run size is bounded by the build setting. With that setting fixed,
total work remains linear in input length. Raising the limit increases both
the memory requirement and worst-case sorting work per run.

## Avoid searches that cannot succeed

One packed property lookup says whether a character decomposes, its combining
class, and whether it can take part in composition. Most characters do not
decompose, so they need no search through decomposition mappings. Two bits
rule out impossible composition pairs before a pair-table search.

Hangul decomposition and composition use arithmetic instead of stored mappings.
Other canonical decompositions use generated tables. A four-entry scratch
array holds one fully decomposed scalar; four is the maximum checked against
the pinned Unicode data by the property tests.

NFC composition tracks the last retained combining class to decide whether
an intervening mark blocks a pair. It also handles composition across starters,
including Hangul, instead of assuming every new starter must end output.

## Answer common queries without writing normalized text

Canonical equality advances two NFD iterators together and compares their
scalars. It needs no complete output buffers and can stop at the first
difference. Strict UTF-8 handling prevents different malformed byte strings
from comparing equal merely because both became replacement characters.

`isNormalized` uses Unicode quick-check properties and combining order. NFD
can reject a decomposable character immediately. NFC has a third quick-check
answer, `Maybe`: the preceding context decides whether composition changes it.

When decomposed marks cannot reorder around the current character, a local
composition check settles that `Maybe`. If reordering might matter, the code
normalizes and compares the relevant prefix using the real algorithm. It does
not treat `Maybe` as `Yes`. This saves work on common already-normalized input
while retaining the full check where it is needed.

## Bound output space separately

The UTF-8 capacity bound is generated from pinned data. Both forms currently
need at most three times the input byte count; NFC can grow too because some
decompositions are excluded from recomposition. Multiplication is checked for
overflow. The output bound says nothing about UTF-8 validity or run length.

[Normalization tests](../../src/normalization_test.zig) cover Unicode fixtures,
ordering, composition, malformed input, buffer limits, partial results, and
query shortcuts. Property-generator tests check the scratch-size and expansion
bounds against the pinned data.
