# zunic

Allocation-free Unicode primitives for Zig 0.16.0 or later.

Measure width, iterate graphemes and words, wrap text, find line endings, trim
whitespace, and normalize Unicode. Strip ANSI escapes or track formatting as
you iterate.

> [!CAUTION] 
>
> If you are against using AI-generated code, **DO NOT** use this library in your projects.
>
> zunic development makes extensive use of AI tools, and AI-generated code can be found throughout the codebase.

## Why zunic

- **Fast.** On par with corresponding Rust libraries in our benchmarks,
  and faster on many workloads.
- **No allocation.** Views borrow your bytes. Iterators return byte
  ranges; normalization and ANSI stripping write into a buffer you supply.
- **Wrap without breaking.** Measure whole grapheme clusters and wrap
  without splitting them.
- **Use what you need.** Ask for width, boundaries, or normalized text
  without building a larger object.
- **Parsed terminal formatting.** Track ANSI styles and hyperlinks as you iterate.
- **Zig only.** No external libraries.
- **Tested.** Tests cover Unicode rules, fast paths, and edge cases.

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
    const capacity = comptime try zunic.text(input).normalizedLenBound(.nfc); // 18 bytes
    var buffer: [capacity]u8 = undefined;
    const normalized = try zunic.text(input).normalize(.nfc).writeTo(&buffer);
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

`text()` treats input as plain text. Use `terminal().stripAnsi()` before
measuring or wrapping input containing ANSI escapes.
Display operations tolerate malformed UTF-8; normalization rejects it and has a
[configurable combining-run limit](docs/text/normalization/README.md#combining-run-limit).
Call `try text.validate()` first when malformed UTF-8 should be rejected.
Word boundaries are locale-independent and do not use dictionaries.

## Terminal text

`zunic.terminal(bytes)` provides byte-only ANSI stripping and token iteration.
It recognizes a subset of CSI and OSC commands, including SGR formatting and
OSC 8 hyperlinks.

```zig
const styled = "\x1b[1;31mHello\x1b[0m";
var buffer: [styled.len]u8 = undefined;
const plain = try zunic.terminal(styled).stripAnsi(&buffer);
std.debug.print("width: {d}\n", .{zunic.text(plain).width()}); // 5

var tokens = zunic.terminal(styled).tokens().iterator();
const fields = (try tokens.next()).?.escape.effect.sgr;
std.debug.print("sets bold: {any}\n", .{fields.bold}); // true
std.debug.print("active bold: {any}\n", .{tokens.state.bold}); // true
```

Tokens return grapheme spans or escapes with `.sgr`, `.hyperlink`, or `.other`
effects. SGR effects list affected fields and flag unsupported or invalid
parameters as `unhandled`. Read resulting values from `iterator.state`.
State updates before the command is returned; links borrow the original input.

Token iteration reports `EscapeInsideGrapheme` when it reaches content that joins
across an escape. Earlier tokens and state updates are not rolled back. `stripAnsi()`
simply removes recognized commands, without UTF-8 validation or grapheme checks.
Terminal width and styled wrapping are not provided yet.

See the [terminal API](docs/terminal/README.md), [state layout](docs/terminal/state.md),
and [native benchmarks](docs/terminal/benchmarks.md). State tracking adds work,
especially on command-heavy input; the Rust comparison above covers text operations.

## Standards

Zunic uses **Unicode 16.0.0** data:

| Standard | Used for |
| --- | --- |
| [UAX #29: Unicode Text Segmentation](https://www.unicode.org/reports/tr29/tr29-45.html) | Extended grapheme clusters and default word boundaries |
| [UAX #14: Unicode Line Breaking Algorithm](https://www.unicode.org/reports/tr14/tr14-53.html) | Line-break opportunities and hard terminators |
| [UAX #11: East Asian Width](https://www.unicode.org/reports/tr11/tr11-43.html) | Width properties used by Zunic's terminal-column policy |
| [UAX #15: Unicode Normalization Forms](https://www.unicode.org/reports/tr15/) | NFC, NFD, NFKC, NFKD, and canonical/compatibility equality |
| [UAX #44: Unicode Character Database](https://www.unicode.org/reports/tr44/tr44-36.html) | The `White_Space` property used by trimming |

Terminal column counts and line fitting are Zunic policies built on these rules
and properties. See the [known line-break limitation](docs/text/wrap/implementation.md#known-limitation).

Escape handling uses a subset of [ECMA-48](https://ecma-international.org/publications-and-standards/standards/ecma-48/)
and [XTerm control sequences](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html),
with [OSC 8 hyperlinks](https://gist.github.com/egmontkob/eb114294efbcd5adb1944c9f3cb5feda)
and [colored and styled underlines](https://sw.kovidgoyal.net/kitty/underlines/).

## Documentation

See [docs/](docs/README.md) for signatures, return values, examples, and
implementation decisions:

[Text view](docs/text/README.md) ·
[Terminal view](docs/terminal/README.md) ·
[API overview](docs/README.md#api-overview)

Run `zig build test` for the test suite or `zig build docs-test` for the
documentation examples. Build options and verification details are in
[the architecture notes](docs/internals/README.md).

Rust comparison benchmarks live in [bench-vs-rust/](bench-vs-rust/README.md).
Run `make -C bench-vs-rust build`, `test`, or `bench` from a source checkout.
Cargo fetches the pinned Rust dependencies when needed.
