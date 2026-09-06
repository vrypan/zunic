# zunic

Allocation-free Unicode primitives for Zig terminal applications.

The package currently provides tolerant UTF-8 stepping, Unicode 16.0.0
extended-grapheme segmentation, default Unicode 16.0.0 UAX #14 line-break
boundaries, and a terminal cell-width policy. Its grapheme and line-break
implementations pass the official Unicode 16.0.0 conformance fixtures.

Open a lens for the question you have: `zunic.graphemes(bytes)` partitions
user-visible text, `zunic.wrap(bytes, options)` chooses display lines, and
`zunic.lines(bytes)` exposes hard-break-delimited lines. Lenses borrow their
input, do not allocate, and scan only when iterated or counted.

## Why zunic

- **No allocator, anywhere.** No API takes an `std.mem.Allocator`, so
  nothing can fail on allocation. Iterators return borrowed byte offsets
  into the caller's input; state lives in the iterator struct.
- **No dependencies.** Zig standard library only. The Unicode tables are
  generated into the source tree, so there is no build-time download,
  code generation step, or C library to link.
- **Conformance-tested, not hand-tuned.** `zig build test` runs the
  official Unicode 16.0.0 `GraphemeBreakTest` and `LineBreakTest`
  fixtures, embedded in the repository, over every case they define.
- **Tolerant.** Malformed UTF-8 never errors and never
  panics. An invalid byte is consumed as one span with defined fallback
  properties, so a terminal reading arbitrary bytes keeps making
  progress.
- **Question-shaped API.** Typed byte, grapheme, and column coordinates keep
  coordinate systems distinct. Use `.measured()` only when a render loop
  needs a cluster's terminal width.
- **Optimized wrapping.** Grapheme segmentation, UAX #14 boundaries, and
  terminal widths are fused only where wrapping needs all three facts.
- **Checked ASCII fast path.** Runs of plain ASCII take a vectorized
  scan on aarch64 and x86_64. It is portable `@Vector` code with no
  intrinsics, checked against the scalar implementation for every byte
  value at every alignment. It needs no configuration, and the backend
  is selectable at build time.

## Usage

Add the dependency:

```sh
zig fetch --save git+https://github.com/vrypan/zunic.git#v0.3.0
```

Add the module in your application's `build.zig`:

```zig
const zunic = b.dependency("zunic", .{});
exe.root_module.addImport("zunic", zunic.module("zunic"));
```

No build flags are required. The vectorized ASCII fast path is enabled by
default wherever a backend exists, currently aarch64 and x86_64, and falls
back to the scalar path everywhere else. To pin a backend, pass the option
through the dependency rather than to your own build:

```zig
const zunic = b.dependency("zunic", .{ .@"wrap-fast-path" = .off });
```

Accepted values are `.auto` (the default), `.scalar`, `.simd`, and `.off`.
`-Dwrap-fast-path` applies when building zunic itself, such as running its
tests or benchmarks.

Then import `zunic` in application code. This example opens a measured
grapheme lens and reads its borrowed spans:

```zig
const std = @import("std");
const zunic = @import("zunic");

pub fn main() void {
    const text = "Hello, 👋 world";

    var graphemes = zunic.graphemes(text).measured().iterator();
    while (graphemes.next()) |span| {
        const cluster = text[span.start.value..span.end.value];
        std.debug.print("{s}: {} columns\n", .{
            cluster,
            span.columns,
        });
    }
}
```

## Wrapping terminal text

`zunic.wrap` opens greedy display lines by terminal columns. It preserves
extended grapheme clusters and default UAX #14 break opportunities. Hard line
separators are consumed rather than included in the returned span.

```zig
var lines = (try zunic.wrap(text, .{ .max_columns = 80 })).iterator();
while (lines.next()) |line| {
    const visible = text[line.start.value..line.end.value];
    std.debug.print("{s} ({d} columns)\n", .{ visible, line.columns.value });
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
