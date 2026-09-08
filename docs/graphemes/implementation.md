# Grapheme implementation decisions

[API](README.md) · [Shared architecture](../architecture.md)

The reference `ClusterState` in [grapheme.zig](../../src/grapheme.zig) expresses
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

Malformed tokens advance one byte with the `Other` grapheme category and no
width. The normal boundary rules still apply: this is tolerant traversal, not
replacement encoding or validation.

[Conformance tests](../../src/conformance_test.zig) exercise pinned Unicode
fixtures. [Scanner tests](../../src/scan_test.zig) also compare compiled
grapheme transitions with the reference rules on byte streams.
