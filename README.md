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
pub fn columnAt(bytes: []const u8, offset: ByteOffset) Column
pub fn byteAt(bytes: []const u8, column: Column) ColumnHit
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
| `ColumnHit` | `cluster: Span`, `column: Column` | Grapheme covering a requested column and its starting column |
| `Line` | `start: ByteOffset`, `end: ByteOffset`, `columns: Column` | One wrapped display line |

Use `bytes[span.start.value..span.end.value]` to recover the borrowed content.
`MeasuredSpan.renderable` lets a renderer distinguish a normally renderable
zero-, one-, or two-column cluster from input that its terminal policy should
drop or replace.

### Grapheme lenses

`zunic.graphemes(bytes)` applies the default Unicode 16.0.0 extended-grapheme
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
const indexed = zunic.graphemes(text).indexed(&storage);

const middle = indexed.at(.init(1)).?;
const cluster = text[middle.start.value..middle.end.value]; // "界"
```

Measurement can be requested before any other lens operation:

```zig
const measured = zunic.graphemes(text).measured();
const count = measured.count();
const first = measured.at(.init(0)); // ?zunic.MeasuredSpan
```

### Width and coordinate conversion

`zunic.width(bytes)` returns the terminal-cell width of the complete input.
Width is computed by grapheme cluster so emoji and regional-indicator sequences
are not counted scalar by scalar. Control characters and malformed bytes have
no display width under the package policy.

`zunic.columnAt(bytes, offset)` maps a byte offset to a display column. An
offset inside a multibyte or multi-scalar grapheme maps to that grapheme's
starting column. An offset at or beyond the end maps to the total width.

`zunic.byteAt(bytes, column)` performs the inverse query and returns the whole
grapheme plus its actual starting column. The distinction matters when the
requested column lands in the second cell of a wide grapheme:

```zig
const text = "a界b";
const hit = zunic.byteAt(text, .init(2));

// Column 2 is the second cell of 界, whose real start is column 1.
std.debug.assert(hit.column.value == 1);
std.debug.assert(hit.cluster.start.value == 1);
```

When the requested column is past the text, `cluster` is an empty span at the
end and `column` is the total display width. Leading zero-width graphemes map
to their earliest matching position.

### Wrapping and hard-delimited lines

The wrapping types are:

```zig
pub const Overflow = enum { allow, grapheme };

pub const WrapOptions = struct {
    max_columns: usize,
    overflow: Overflow = .grapheme,
};
```

`zunic.wrap(bytes, options)` returns a `Wrapped` lens with:

- `.iterator()`, whose `.next()` returns `?zunic.Line`;
- `.count()`, which scans and counts all returned lines.

The algorithm is greedy: it chooses the last legal Unicode line-break
opportunity that fits within `max_columns`. With `.overflow = .grapheme`, an
unbreakable run is split at a grapheme boundary. With `.overflow = .allow`, the
run remains on an oversized line until a legal opportunity is found.

`zunic.lines(bytes)` has the same `Wrapped` interface but no practical column
limit. It therefore splits only at mandatory hard line separators. Hard
separator bytes are consumed and excluded from the returned line span.

Neither operation trims returned spans. Spaces and other non-separator bytes
remain part of the borrowed line.

### Unicode line-break boundaries

`zunic.line_break` exposes the default, locale-independent Unicode 16.0.0 UAX
#14 boundary iterator:

```zig
pub const Opportunity = enum {
    prohibited,
    allowed,
    mandatory,
};

pub const Boundary = struct {
    offset: usize,
    opportunity: Opportunity,
};

pub fn iterator(bytes: []const u8) Iterator;
```

Unlike APIs that yield only usable breaks, this iterator returns every scalar
boundary, including `.prohibited` ones. Non-empty input begins with a
prohibited boundary at offset zero and ends with a mandatory boundary at
`bytes.len`; empty input produces one mandatory boundary at offset zero.

```zig
var boundaries = zunic.line_break.iterator(text);
while (boundaries.next()) |boundary| {
    switch (boundary.opportunity) {
        .prohibited => {},
        .allowed => std.debug.print("may break at {d}\n", .{boundary.offset}),
        .mandatory => std.debug.print("must break at {d}\n", .{boundary.offset}),
    }
}
```

The iterator implements default UAX #14 opportunities. It does not perform
terminal-width fitting, locale tailoring, or dictionary segmentation for
complex South East Asian text. Use `zunic.wrap` when the desired result is a
sequence of display lines rather than the complete boundary stream.

`zunic.line_break.Iterator` is the concrete type returned by `iterator` and
its user-facing operation is `.next()`. The module also exports `State` and
`isHardClass` for the package's low-level scanner composition; ordinary callers
should prefer the boundary iterator rather than depending on machine state.

### Tolerant UTF-8 stepping

`zunic.utf8.step` is the lowest-level public operation:

```zig
pub const Step = struct {
    len: usize,
    cp: ?u21,
};

pub fn step(bytes: []const u8) Step;
```

For a valid leading scalar, `len` is its encoded byte length and `cp` contains
the code point. For non-empty malformed input, `len` is one and `cp` is null,
so callers always make progress. Empty input returns `.len = 0` and
`.cp = null`.

```zig
var offset: usize = 0;
while (offset < bytes.len) {
    const decoded = zunic.utf8.step(bytes[offset..]);

    if (decoded.cp) |cp| {
        std.debug.print("U+{X}\n", .{cp});
    } else {
        std.debug.print("invalid byte at {d}\n", .{offset});
    }
    offset += decoded.len;
}
```

Higher-level APIs use the same recovery rule. Each invalid byte forms one
advancing, AL-like fallback scalar for line breaking and contributes no
terminal columns.

### Diagnostic exports

`zunic.build_options.wrap_fast_path` reports the resolved wrapping fast-path
selection. `zunic.testing.instrumentedIterator` exposes the wrapping
work-bound counters used by this package's tests; application code should use
`zunic.wrap` instead.

## Development

Run `make benchmark` to measure ReleaseFast throughput for UTF-8, grapheme,
width, line-break, and wrapping workloads. It reports seven samples per case;
compare results on the same machine rather than treating them as
cross-machine rankings. Use `make benchmark` with
`BENCHMARK_ARGS=--smoke` for a quicker smoke run.

```sh
zig build test
```
