# zunic

Allocation-free Unicode primitives for Zig terminal applications.

The package currently provides tolerant UTF-8 stepping, Unicode 16.0.0
extended-grapheme segmentation, default Unicode 16.0.0 UAX #14 line-break
boundaries, and a terminal cell-width policy. Its grapheme and line-break
implementations pass the official Unicode 16.0.0 conformance fixtures.

`zunic.scalar.iterator(bytes)` is the low-level compositional API. It yields
borrowed byte spans, an optional decoded code point, and its grapheme and
line-break properties; malformed bytes consume one byte with the package's
normal fallback properties.

`zunic.line_break.iterator(bytes)` returns a boundary at every UTF-8
code-point byte offset, including offset zero and the end of the input. Each boundary is
`.prohibited`, `.allowed`, or `.mandatory`; the final boundary is mandatory.
The iterator is allocation-free and reports default UAX #14 opportunities only.
Choosing a break for a terminal width, locale/CLDR tailoring, dictionary
segmentation, and emergency breaks remain caller responsibilities.

## Usage

Add the dependency:

```sh
zig fetch --save git+https://github.com/vrypan/zunic.git#v0.2.0
```

Add the module in your application's `build.zig`:

```zig
const zunic = b.dependency("zunic", .{});
exe.root_module.addImport("zunic", zunic.module("zunic"));
```

Then import `zunic` in application code. This example iterates user-visible
graphemes, measures their terminal width, and prints only usable line-break
boundaries:

```zig
const std = @import("std");
const zunic = @import("zunic");

pub fn main() void {
    const text = "Hello, 👋 world";

    var graphemes = zunic.grapheme.iterator(text);
    while (graphemes.next()) |span| {
        const cluster = text[span.start..span.end];
        std.debug.print("{s}: {} columns\n", .{
            cluster,
            zunic.width.textWidth(cluster),
        });
    }

    var breaks = zunic.line_break.iterator(text);
    while (breaks.next()) |boundary| {
        if (boundary.opportunity != .prohibited) {
            std.debug.print("break at byte {} ({s})\n", .{
                boundary.offset,
                @tagName(boundary.opportunity),
            });
        }
    }
}
```

## Wrapping terminal text

`zunic.wrap.iterator` chooses greedy lines by terminal columns. It preserves
extended grapheme clusters and default UAX #14 break opportunities. Hard line
separators are consumed rather than included in the returned span.

```zig
var lines = try zunic.wrap.iterator(text, .{ .max_columns = 80 });
while (lines.next()) |line| {
    const visible = text[line.start..line.end];
    std.debug.print("{s} ({d} columns)\n", .{ visible, line.columns });
}
```

The iterator prefers the last legal break that fits. The default `.grapheme`
overflow policy then breaks an unbreakable word before the grapheme that would
overflow; use `.overflow = .allow` to keep that run on one oversized line.
Zero-column suffixes remain attached to an oversized line, and a following
hard separator is consumed without producing a phantom line. Spans retain
whitespace, tabs, controls, and malformed bytes; apply the renderer's
filtering policy before writing terminal output.

## Development

Run `make benchmark` to measure ReleaseFast throughput for UTF-8, grapheme,
width, line-break, and wrapping workloads. It reports seven samples per case;
compare results on the same machine rather than treating them as
cross-machine rankings. Use `make benchmark` with
`BENCHMARK_ARGS=--smoke` for a quicker smoke run.

```sh
zig build test
```
