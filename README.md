# zunic

Allocation-free Unicode primitives for Zig terminal applications.

The package currently provides tolerant UTF-8 stepping, Unicode 16.0.0
extended-grapheme segmentation, default Unicode 16.0.0 UAX #14 line-break
boundaries, and a terminal cell-width policy. Its grapheme and line-break
implementations pass the official Unicode 16.0.0 conformance fixtures.

Open a lens for the question you have. `zunic.text(bytes)` is a view over
borrowed bytes and its methods are the questions: `.graphemes()` partitions
user-visible text, `.width()` measures terminal columns, `.wrap(options)`
chooses display lines, and `.terminators()` locates hard line breaks.
Lenses borrow their input, do not allocate, and scan only when iterated or
counted.

> **Strip ANSI escape sequences before using `zunic.text`.**
> It reads every byte as content, so an escape sequence is measured as the
> ordinary characters it is made of. `"\x1b[31mred\x1b[0m"` reports a width
> of 10 rather than 3, and wrapping it to 3 columns yields
> `"\x1b[31"`, `"mre"`, `"d\x1b[0"`, `"m"` -- breaks land inside the
> sequence and the output is corrupt. This is a deliberate boundary: `text`
> makes no attempt to recognise terminal control sequences. A `terminal` lens
> that does may be added later.

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

    var graphemes = zunic.text(text).graphemes().measured().iterator();
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

`zunic.text(bytes).wrap(options)` opens greedy display lines by terminal columns. It preserves
extended grapheme clusters and default UAX #14 break opportunities. Hard line
separators are consumed rather than included in the returned span.

```zig
var lines = (try zunic.text(text).wrap(.{ .max_columns = 80 })).iterator();
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

## API reference

All text parameters are borrowed `[]const u8` slices. Opening a lens does not
scan or allocate; work happens when a method or iterator is consumed. Returned
offsets are relative to the exact slice passed to the function.

### Top-level functions

```zig
pub fn graphemes(bytes: []const u8) Graphemes
pub fn wrap(bytes: []const u8, options: WrapOptions) error{InvalidWidth}!Wrapped
pub fn lines(bytes: []const u8) Wrapped
pub fn width(bytes: []const u8) usize
```

`wrap` returns `error.InvalidWidth` when `max_columns` is zero. The other
top-level functions do not return errors, including for malformed UTF-8.

### Coordinates and returned values

Byte offsets, grapheme indices, and display columns are deliberately distinct
types. Each coordinate has a public `value: usize` field and an `init` helper:

```zig
const byte_offset = zunic.ByteOffset.init(12);
const grapheme_index = zunic.GraphemeIndex.init(3);
const column = zunic.Column.init(20);
```

| Type | Fields | Meaning |
| --- | --- | --- |
| `ByteOffset` | `value: usize` | Byte position relative to the input slice |
| `GraphemeIndex` | `value: usize` | Zero-based extended-grapheme index |
| `Column` | `value: usize` | Zero-based terminal display column |
| `Span` | `start: ByteOffset`, `end: ByteOffset` | Half-open borrowed byte range |
| `MeasuredSpan` | `start`, `end`, `columns: u2`, `renderable: bool` | Grapheme range plus terminal measurement |
| `Line` | `start: ByteOffset`, `end: ByteOffset`, `columns: Column` | One wrapped display line |

Use `bytes[span.start.value..span.end.value]` to recover the borrowed content.
`MeasuredSpan.renderable` lets a renderer distinguish a normally renderable
zero-, one-, or two-column cluster from input that its terminal policy should
drop or replace.

### Grapheme lenses

`zunic.text(bytes).graphemes()` applies the default Unicode 16.0.0 extended-grapheme
rules and provides these methods:

| Method | Result | Cost |
| --- | --- | --- |
| `.iterator()` | Iterator whose `.next()` returns `?Span` | One lazy forward pass |
| `.count()` | Number of grapheme clusters | Scans the complete input |
| `.at(GraphemeIndex)` | `?Span` | Scans from the beginning |
| `.measured()` | Grapheme lens returning `MeasuredSpan` | Opening is O(1); measurement occurs while scanning |
| `.indexed(buffer)` | Caller-owned indexed view | Scans to count and fill the buffer |

The buffer passed to `.indexed()` must have room for every grapheme. The
returned view exposes `.count()` and O(1) `.at(GraphemeIndex)` without owning
or allocating storage:

```zig
const text = "a界b";
var storage: [3]zunic.Span = undefined;
const indexed = zunic.text(text).graphemes().indexed(&storage);

const middle = indexed.at(.init(1)).?;
const cluster = text[middle.start.value..middle.end.value]; // "界"
```

Measurement can be requested before any other lens operation:

```zig
const measured = zunic.text(text).graphemes().measured();
const count = measured.count();
const first = measured.at(.init(0)); // ?zunic.MeasuredSpan
```

### Width and coordinate conversion

`zunic.text(bytes).width()` returns the terminal-cell width of the complete input.
Width is computed by grapheme cluster so emoji and regional-indicator sequences
are not counted scalar by scalar. Control characters and malformed bytes have
no display width under the package policy.

`zunic.text(bytes).terminators()` locates the hard line breaks as byte
extents. Seven code points terminate a line -- `U+000A` LF, `U+000B` VT,
`U+000C` FF, `U+000D` CR, `U+0085` NEL, `U+2028` and `U+2029` -- and `\r\n`
is reported as a single terminator two bytes long.

Paragraph content is the gaps between them:

```zig
var pos: usize = 0;
var it = zunic.text(text).terminators().iterator();
while (it.next()) |t| {
    const paragraph = text[pos..t.start.value];
    pos = t.end.value;
}
if (pos < text.len) {
    const paragraph = text[pos..];
}
```

There is no `columnAt` or `byteAt`. Both were sums over
`graphemes().measured()`, so callers write the loop they need:

```zig
var column: usize = 0;
var it = zunic.text(text).graphemes().measured().iterator();
while (it.next()) |span| : (column += span.columns) {
    if (offset < span.end.value) break;
}
```

## Development

Run `make benchmark` to measure ReleaseFast throughput for UTF-8, grapheme,
width, line-break, and wrapping workloads. It reports seven samples per case;
compare results on the same machine rather than treating them as
cross-machine rankings. Use `make benchmark` with
`BENCHMARK_ARGS=--smoke` for a quicker smoke run.

```sh
zig build test
```
