# zunic

Allocation-free Unicode primitives for Zig 0.16.0 or later.

Measure terminal columns, iterate graphemes and word boundaries, wrap text,
find hard line terminators, and normalize to NFC or NFD.

## Why zunic

- **Fast.** Zunic's performance is broadly on par with corresponding Rust
  libraries such as `unicode-segmentation`, `unicode-normalization`, and
  `textwrap`, and faster on many tested workloads.
- **No allocator needed.** Text views borrow your bytes. Iterators return byte
  ranges; normalization writes into a buffer you supply.
- **Useful for terminal layout.** Measure whole grapheme clusters and wrap
  without splitting them. Byte offsets let you slice the original text directly.
- **Small, separate operations.** Ask for width, boundaries, or normalized text
  without building a larger text object.
- **Zig only.** No external libraries. Unicode tables are included, with no
  code generation or data downloads during a normal build.
- **Tested rules and shortcuts.** Tests cover the pinned Unicode fixtures,
  ASCII fast paths, and limits on repeated scanning.

## Install

```sh
zig fetch --save git+https://github.com/vrypan/zunic.git#v0.3.0
```

In your application's `build.zig`:

```zig
const zunic = b.dependency("zunic", .{});
exe.root_module.addImport("zunic", zunic.module("zunic"));
```

## Example

```zig
const std = @import("std");
const zunic = @import("zunic");

pub fn main() !void {
    const bytes = "Hello, 世界!";
    const text = zunic.text(bytes);

    // Terminal width: 12 columns.
    std.debug.print("width: {d}\n", .{text.width()});

    // Each result is a byte range in the original input.
    var graphemes = text.graphemes().iterator();
    while (graphemes.next()) |span| {
        std.debug.print("grapheme: {s}\n", .{bytes[span.start.value..span.end.value]});
    }

    // Wrap to eight columns, keeping grapheme clusters intact.
    var lines = (try text.wrap(.{ .max_columns = 8 })).iterator();
    while (lines.next()) |line| {
        std.debug.print("line: {s}\n", .{bytes[line.start.value..line.end.value]});
    }

    // Word boundaries include separators; keep only word-like segments.
    const sentence = "Hello, world!";
    var words = zunic.text(sentence).wordBounds().iterator();
    while (words.next()) |word| {
        if (word.is_word) {
            std.debug.print("word: {s}\n", .{sentence[word.start.value..word.end.value]});
        }
    }

    // Compose an accent into NFC, using caller-owned storage.
    const input = "cafe\u{0301}";
    const capacity = comptime try zunic.normalizedLenBound(input.len, .nfc); // 18 bytes
    var buffer: [capacity]u8 = undefined;
    const normalized = try zunic.normalize(input, .nfc).writeTo(&buffer);
    std.debug.print("normalized: {s}\n", .{normalized}); // café
    std.debug.print("normalized width: {d}\n", .{zunic.text(normalized).width()}); // 4

    // Before: 6 bytes, 4 graphemes. After NFC: 5 bytes, 4 graphemes.
    for ([_][]const u8{ input, normalized }) |sample| {
        var it = zunic.text(sample).graphemes().iterator();
        var count: usize = 0;
        while (it.next() != null) count += 1;
        std.debug.print("{d} bytes, {d} graphemes\n", .{ sample.len, count });
    }
}
```

Input is plain text: strip ANSI escape sequences before measuring or wrapping.
Display operations tolerate malformed UTF-8; normalization rejects it and has a
[configurable combining-run limit](docs/normalization/README.md#combining-run-limit).
Word boundaries are locale-independent and do not use dictionaries.

## Unicode standards

Zunic uses **Unicode 16.0.0** data:

| Standard | Used for |
| --- | --- |
| [UAX #29: Unicode Text Segmentation](https://www.unicode.org/reports/tr29/tr29-45.html) | Extended grapheme clusters and default word boundaries |
| [UAX #14: Unicode Line Breaking Algorithm](https://www.unicode.org/reports/tr14/tr14-53.html) | Line-break opportunities and hard terminators |
| [UAX #11: East Asian Width](https://www.unicode.org/reports/tr11/tr11-43.html) | Width properties used by Zunic's terminal-column policy |
| [UAX #15: Unicode Normalization Forms](https://www.unicode.org/reports/tr15/) | NFC, NFD, and canonical equality |

Terminal column counts and line fitting are Zunic policies built on these rules
and properties. See the [known line-break limitation](docs/wrap/implementation.md#known-limitation).

## Documentation

See [docs/](docs/README.md) for signatures, return values, examples, and
implementation decisions:

[Graphemes](docs/graphemes/README.md) ·
[Width](docs/width/README.md) ·
[Wrap](docs/wrap/README.md) ·
[Terminators](docs/terminators/README.md) ·
[Word boundaries](docs/word-bounds/README.md) ·
[Normalization](docs/normalization/README.md)

Run `zig build test` for the test suite or `zig build docs-test` for the
documentation examples. Build options and verification details are in
[the architecture notes](docs/architecture.md).
