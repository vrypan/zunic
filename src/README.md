# zooi Unicode component

This directory is an allocation-free internal component with no dependency on
the rest of zooi. It provides tolerant UTF-8 stepping, extended-grapheme
grouping, a terminal-width policy, and simple line-break opportunities.

`tables.zig` is the checked-in Unicode 16.0.0 width data previously used by
zooi. Normal builds are offline. The terminal-width policy is deliberately not
a claim that every terminal renders Unicode identically: emoji clusters and
regional-indicator flags use two cells, ambiguous characters use one, controls
and malformed UTF-8 are ignored, and clusters wider than two cells have an
explicit caller-visible replacement path.

The grapheme implementation passes Unicode 16.0.0's official
`GraphemeBreakTest` fixture, including combining marks, Hangul,
prepend/spacing marks, Indic conjuncts, flags, and emoji ZWJ sequences. Line
breaking currently offers mandatory CRLF/LF breaks and whitespace
opportunities. Its Unicode 16 property tables are checked in, but the complete
context-sensitive UAX #14 state machine remains future work.
