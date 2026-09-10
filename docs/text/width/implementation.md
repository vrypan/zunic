# Width implementation decisions

[API](README.md) · [Grapheme implementation](../graphemes/implementation.md)

[width.zig](../../../src/layout/width.zig) first asks whether every byte is printable
ASCII (`0x20..0x7E`). If so, the answer is exactly the slice length: each byte
is a one-column cluster. This shortcut excludes controls and non-ASCII bytes,
so it cannot miss combining or emoji behavior.

The detector in [ascii_scan.zig](../../../src/layout/ascii_scan.zig) can examine 16 bytes
at a time using portable Zig vectors. It reads only complete in-bounds chunks,
then checks the tail scalarly. `-Dwrap-fast-path=off|scalar|auto|simd` selects
the detector backend for width as well as wrapping. Auto uses vectors on
aarch64 and x86_64 for sufficiently long inputs; other cases use scalar checks.

If the whole input is not printable ASCII, the mixed path measures ASCII runs
in bulk. Printable bytes count as one column; C0 controls and DEL count as
zero. Before handing a non-ASCII region to the grapheme engine, it gives back
the last ASCII byte: that byte may be the base of a cluster continuing into
the next region, as in `a` followed by a combining accent. Bulk counting resumes
only at a grapheme boundary reported by the engine.

After eight consecutive probes that find fewer than 16 ASCII bytes, the loop
uses the grapheme engine for the remainder. This avoids repeated probes on
dense non-ASCII text. These thresholds affect speed, not measured width.
The engine uses the same `ClusterMeasure` as measured graphemes, keeping the
two APIs' policy aligned. A failed whole-input check can inspect a prefix
before the mixed path repeats it; total work remains linear in byte length.

The mixed path still counts ASCII runs scalarly with `wrap-fast-path=off`;
that option disables the whole-input shortcut and vector probes, not all
ASCII handling. Run and whole-line probes use scalar scans off supported
vector targets and when vectors are disabled.

The mixed loop is `noinline` to keep its code size out of the ASCII dispatch's
inlining budget. This is a compiler-specialization choice, not a different
measurement rule. The one-cell replacement for oversized ordinary clusters
and the two-cell pictographic rule are explicit terminal policy choices.

[Root tests](../../../src/root_test.zig) compare public measurements with cluster
measurement; [scanner tests](../../../src/scan_test.zig) compare ASCII detectors
across backends and alignments.
