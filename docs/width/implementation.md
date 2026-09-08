# Width implementation decisions

[API](README.md) · [Grapheme implementation](../graphemes/implementation.md)

[width.zig](../../src/width.zig) first asks whether every byte is printable
ASCII (`0x20..0x7E`). If so, the answer is exactly the slice length: each byte
is a one-column cluster. This shortcut excludes controls and non-ASCII bytes,
so it cannot miss combining or emoji behavior.

The detector in [ascii_scan.zig](../../src/ascii_scan.zig) can examine 16 bytes
at a time using portable Zig vectors. It reads only complete in-bounds chunks,
then checks the tail scalarly. `-Dwrap-fast-path=off|scalar|auto|simd` selects
the detector backend for width as well as wrapping. Auto uses vectors on
aarch64 and x86_64 for sufficiently long inputs; other cases use scalar checks.

If detection fails, the general path segments and measures graphemes together.
It uses the same `ClusterMeasure` as measured graphemes, keeping the two APIs'
policy aligned. A failed ASCII check can inspect a prefix before the general
scan repeats it; the overall work is still linear in byte length.

The general loop is `noinline` to keep its code size out of the ASCII dispatch's
inlining budget. This is a compiler-specialization choice, not a different
measurement rule. The one-cell replacement for oversized ordinary clusters
and the two-cell pictographic rule are explicit terminal policy choices.

[Root tests](../../src/root_test.zig) compare public measurements with cluster
measurement; [scanner tests](../../src/scan_test.zig) compare ASCII detectors
across backends and alignments.
