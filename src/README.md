# zooi Unicode component

This directory is an allocation-free internal component with no dependency on
the rest of zooi. It provides tolerant UTF-8 stepping, extended-grapheme
grouping, a terminal-width policy, and default UAX #14 line-break boundaries.

`tables.zig` is the checked-in Unicode 16.0.0 width data previously used by
zooi. Normal builds are offline. The terminal-width policy is deliberately not
a claim that every terminal renders Unicode identically: emoji clusters and
regional-indicator flags use two cells, ambiguous characters use one, controls
and malformed UTF-8 are ignored, and clusters wider than two cells have an
explicit caller-visible replacement path.

The grapheme implementation passes Unicode 16.0.0's official
`GraphemeBreakTest` fixture, including combining marks, Hangul,
prepend/spacing marks, Indic conjuncts, flags, and emoji ZWJ sequences. The
line-break iterator passes Unicode 16.0.0's `LineBreakTest` and yields one
boundary for each UTF-8 code-point byte offset: offset zero is prohibited, the final
offset is mandatory, and intermediate positions are prohibited or allowed.
It implements UAX #14 revision 53 defaults, without locale/CLDR tailoring,
dictionary segmentation for SA text, terminal-width line fitting, or emergency
breaking.

`wrap.iterator(bytes, .{ .max_columns = n })` adds a separate terminal policy:
it chooses the last fitting legal boundary, never splits an extended grapheme,
and consumes hard Unicode line separators. When an unbreakable run is already
oversized, zero-column suffixes stay attached and its following separator does
not create a phantom line. It is not locale tailoring or hyphenation.
