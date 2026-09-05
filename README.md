# zunic

Allocation-free Unicode primitives for Zig terminal applications.

The package currently provides tolerant UTF-8 stepping, Unicode 16.0.0
extended-grapheme segmentation, default Unicode 16.0.0 UAX #14 line-break
boundaries, and a terminal cell-width policy. Its grapheme and line-break
implementations pass the official Unicode 16.0.0 conformance fixtures.

`zunic.line_break.iterator(bytes)` returns a boundary at every UTF-8
code-point byte offset, including offset zero and the end of the input. Each boundary is
`.prohibited`, `.allowed`, or `.mandatory`; the final boundary is mandatory.
The iterator is allocation-free and reports default UAX #14 opportunities only.
Choosing a break for a terminal width, locale/CLDR tailoring, dictionary
segmentation, and emergency breaks remain caller responsibilities.

```sh
zig build test
```

Use `src/root.zig` as the `zunic` module root.
