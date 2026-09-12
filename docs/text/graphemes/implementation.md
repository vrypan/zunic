# Grapheme implementation decisions

[API](README.md) · [Shared architecture](../../internals/README.md)

The reference `ClusterState` in [grapheme.zig](../../../src/segmentation/grapheme.zig) expresses
the boundary rules and state updates. At compile time, the engine evaluates
them into transition tables. Runtime traversal uses a category and state ID to
obtain both the next state and the boundary decision, avoiding a chain of rule
branches for every scalar.

The state retains exactly the context needed for CRLF, Hangul, Indic conjuncts,
emoji ZWJ sequences, and regional-indicator pairing. Regional-indicator history
needs only parity, not an unbounded count. Categories are derived from property
combinations actually present in the pinned Unicode data. These reductions
preserve the reference rule decisions rather than approximating common text.

A pending token carries lookahead across calls: the scalar that establishes
the next boundary does not have to be decoded again to start the next cluster.
Non-ASCII classification uses the shared packed property record; ASCII skips
UTF-8 decoding and uses direct property arrays.

`ClusterMeasure` accumulates width during the same segmentation pass. The public
measured iterator decodes that result instead of scanning the cluster again.
Internally, width value `3` means a one-cell non-renderable replacement; public
results expose this as `columns = 1, renderable = false`. The inline traversal
allows the compiler to discard measurement work when only boundaries are used.

The inline chain includes `decoded_token.at`, the engine's `decodeAt`, `peekToken`,
`takeToken`, and `next`, and the public `text.Iterator(include_measure).next`.
Keeping the whole chain visible lets the consumer eliminate unused token
fields and keep iterator state in registers. Forcing only the decoder inline
can move a call boundary into a token helper; forcing only the internal chain
can make the public wrapper too large for automatic inlining. With Zig 0.16
ReleaseFast on Apple M4, that latter case produced a call per grapheme to a
wrapper with a 320-byte stack frame and regressed unmeasured traversal.

Treat these annotations as a group when tuning them. Check both measured and
unmeasured public traversal with a consumer that reads both span offsets, as
the native benchmark does; a simpler end-offset-only checksum missed the
wrapper regression. Inlining increases caller code size, so inspect emitted
code and benchmark the other scalar consumers as well. These decisions depend
on compiler and target and should be measured again when either changes.

The complete chain was checked against commit `8980ecf` with Zig 0.16.0
ReleaseFast on Apple M4: three full native runs per version, seven samples per
row, with all 298 row checksums matching. Unicode document grapheme traversal
took 45–57% less time, measured document traversal 26–43% less, and document
width 11–45% less. The benchmark's machine-code section grew by 12 KB (3.3%).
Several NFC quick-check rows ran 20–25% slower in the full executable despite
unchanged instructions; those stable cases were within 1% in an isolated
normalization harness whose baseline and candidate machine code was identical.
The full-executable regression remains a tradeoff to check in consumers.
x86_64 compilation and call elimination were checked, but throughput was only
measured on M4.

Malformed tokens advance one byte with the `Other` grapheme category and no
width. The normal boundary rules still apply: this is tolerant traversal, not
replacement encoding or validation.

[Conformance tests](../../../src/conformance_test.zig) exercise pinned Unicode
fixtures. [Scanner tests](../../../src/scan_test.zig) also compare compiled
grapheme transitions with the reference rules on byte streams.
