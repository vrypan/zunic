# zunic

Allocation-free Unicode primitives for Zig 0.16.0 or later.

Measure width, iterate graphemes and words, stream grapheme decisions, fold
case, query Unicode properties, wrap text, find line endings, trim whitespace,
and normalize Unicode.

> [!CAUTION] 
>
> If you are against using AI-generated code, **DO NOT** use this library in your projects.
>
> zunic development makes extensive use of AI tools, and AI-generated code can be found throughout the codebase.

## Why zunic

- **Fast.** On par with corresponding Rust libraries in our benchmarks,
  and faster on many workloads.
- **No allocation.** Codepoint views store one numeric value and text views
  borrow your bytes. Text iterators return codepoint views or byte ranges;
  normalization writes into a buffer you supply.
- **Wrap without breaking.** Measure whole grapheme clusters and wrap
  without splitting them.
- **Use what you need.** Ask for width, boundaries, or normalized text
  without building a larger object.
- **Zig only.** No external libraries.
- **Tested.** Tests cover Unicode rules, fast paths, and edge cases.

Zunic has two basic entry points:

- Use [`zunic.cp(value)`](docs/codepoint/README.md) when you already have a
  Unicode codepoint in a `u21` and want its properties, isolated width, case
  mapping, numeric value, or decomposition.
- Use [`zunic.text(bytes)`](docs/text/README.md) when you have UTF-8 bytes and
  want to iterate codepoints, graphemes, or words, measure or wrap text, find
  line endings, trim whitespace, or normalize the text.

Neither constructor allocates or validates its input. Property lookups and
text operations perform the work when called.

## Install

```sh
zig fetch --save git+https://github.com/vrypan/zunic.git#v0.3.1
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
    // Query a codepoint that is already available as a u21.
    const point = zunic.cp(0x1f600); // 😀
    const terminal = point.terminal();
    std.debug.print("emoji presentation: {}, isolated width: {d}", .{
        terminal.isEmojiPresentation,
        point.width(),
    });
    // Output: emoji presentation: true, isolated width: 2

    // Work with UTF-8 through a borrowed view.
    const bytes = "Hello, 世界!";
    const text = zunic.text(bytes);

    // Terminal width: 12 columns.
    std.debug.print("width: {d}", .{text.width()});
    // Output: width: 12

    // Each result is a byte range in the original input.
    var graphemes = text.graphemes().iterator();
    while (graphemes.next()) |span| {
        std.debug.print("[{s}]", .{bytes[span.start.value..span.end.value]});
    }
    // Output: [H][e][l][l][o][,][ ][世][界][!]

    // Wrap to eight columns, keeping grapheme clusters intact.
    var lines = (try text.wrap(.{ .max_columns = 8 })).iterator();
    while (lines.next()) |line| {
        std.debug.print("[{s}]", .{bytes[line.start.value..line.end.value]});
    }
    // Output: [Hello, ][世界!]

    // Word boundaries include separators; keep only word-like segments.
    const sentence = "Hello, world!";
    var words = zunic.text(sentence).wordBounds().iterator();
    while (words.next()) |word| {
        if (word.is_word) {
            std.debug.print("[{s}]", .{sentence[word.start.value..word.end.value]});
        }
    }
    // Output: [Hello][world]

    // Compose an accent into NFC, using caller-owned storage.
    const input = "cafe\u{0301}";
    const capacity = comptime try zunic.text(input).normalizedLenBound(.nfc); // 18 bytes
    var buffer: [capacity]u8 = undefined;
    const normalized = try zunic.text(input).normalize(.nfc).writeTo(&buffer);
    std.debug.print("normalized: {s}, width: {d}", .{
        normalized,
        zunic.text(normalized).width(),
    });
    // Output: normalized: café, width: 4

    // Before: 6 bytes, 4 graphemes. After NFC: 5 bytes, 4 graphemes.
    for ([_][]const u8{ input, normalized }) |sample| {
        var it = zunic.text(sample).graphemes().iterator();
        var count: usize = 0;
        while (it.next() != null) count += 1;
        std.debug.print("[{d} bytes, {d} graphemes]", .{ sample.len, count });
    }
    // Output: [6 bytes, 4 graphemes][5 bytes, 4 graphemes]
}
```

`text()` treats input as plain text.
Display operations tolerate malformed UTF-8; normalization rejects it and has a
[configurable combining-run limit](docs/text/normalization/README.md#combining-run-limit).
Call `try text.validate()` first when malformed UTF-8 should be rejected.
Word boundaries are locale-independent and do not use dictionaries.

## Standards

Zunic uses **Unicode 17.0.0** data:

| Standard | Used for |
| --- | --- |
| [UAX #29: Unicode Text Segmentation](https://www.unicode.org/reports/tr29/tr29-47.html) | Extended grapheme clusters and default word boundaries |
| [UAX #14: Unicode Line Breaking Algorithm](https://www.unicode.org/reports/tr14/tr14-55.html) | Line-break opportunities and hard terminators |
| [UAX #11: East Asian Width](https://www.unicode.org/reports/tr11/tr11-45.html) | Width properties used by Zunic's terminal-column policy |
| [UAX #15: Unicode Normalization Forms](https://www.unicode.org/reports/tr15/) | NFC, NFD, NFKC, NFKD, and canonical/compatibility equality |
| [UAX #44: Unicode Character Database](https://www.unicode.org/reports/tr44/tr44-37.html) | Scalar properties and the `White_Space` property used by trimming |

Terminal column counts and line fitting are Zunic policies built on these rules
and properties. See the [known line-break limitation](docs/text/wrap/implementation.md#known-limitation).

## Documentation

See [docs/](docs/README.md) for signatures, return values, examples, and
implementation decisions:

[Text view](docs/text/README.md) ·
[API overview](docs/README.md#api-overview)

Run `zig build test` for the test suite or `zig build docs-test` for the
documentation examples. Build options and verification details are in
[the architecture notes](docs/internals/README.md).

Rust comparison benchmarks live in [bench-vs-rust/](bench-vs-rust/README.md).
Run `make -C bench-vs-rust build`, `test`, or `bench` from a source checkout.
Cargo fetches the pinned Rust dependencies when needed.

The like-for-like Zig comparison against uucode lives in
[bench-vs-uucode/](bench-vs-uucode/README.md). Its 15 benchmark classes cover
UTF-8 decoding, grapheme segmentation and width, fused terminal properties,
case operations, numeric and normalization facts, streaming grapheme
boundaries, and Ghostty's scalar-width composition.
