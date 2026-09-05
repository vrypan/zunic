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

## Usage

Add the dependency:

```sh
zig fetch --save git+https://github.com/vrypan/zunic.git#v0.1.0
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

```sh
zig build test
```
