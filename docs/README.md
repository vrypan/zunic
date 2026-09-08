# Zunic documentation

Zunic provides allocation-free Unicode operations over borrowed UTF-8 bytes.
Its Unicode data is pinned to **16.0.0**. Start with [the shared API conventions](conventions.md), then choose an operation:

| Operation | API and examples | Implementation decisions |
| --- | --- | --- |
| Extended grapheme clusters | [graphemes](graphemes/README.md) | [Compiled transitions and shared measurement](graphemes/implementation.md) |
| Terminal columns | [width](width/README.md) | [Width policy and ASCII detection](width/implementation.md) |
| Greedy display lines | [wrap](wrap/README.md) | [Fused scanning, bounded work, and fast paths](wrap/implementation.md) |
| Hard line terminators | [terminators](terminators/README.md) | [Why byte scanning is sufficient](terminators/implementation.md) |
| Default word boundaries | [wordBounds](word-bounds/README.md) | [Decision tables and selective lookahead](word-bounds/implementation.md) |
| NFC/NFD and canonical equality | [normalization](normalization/README.md) | [Bounded runs and quick checks](normalization/implementation.md) |

[Architecture](architecture.md) explains the shared property data, build options,
and verification strategy. Implementation pages describe the current source;
table sizes and private engine types are not public API promises.

Examples assume `const zunic = @import("zunic");` and
`const std = @import("std");` in a module that imports the Zunic dependency.
The runnable versions are in [examples.zig](examples.zig), covered by
`zig build docs-test` and `zig build test` from the repository root.

These pages cover the text-facing API. The separately exported `utf8`,
`line_break`, and `testing` namespaces are lower-level facilities; see their
source documentation when composing custom scanners or work-bound tests.
