# Shared implementation choices

[Documentation index](README.md)

## Borrow bytes and return positions

Most public operations answer questions about the original text. They return
byte positions and column counts instead of allocating substrings. Views cost
only a slice and options; iterators hold their own progress. Callers choose
whether to keep results, render them, or stop early.

Normalization is the exception to returning positions: its output may reorder,
expand, or combine input characters. It returns scalar values or writes UTF-8
into a caller's buffer instead.

## Keep the boundaries enforced, not just tidy

The library is split into Zig modules declared in `build.zig`, not merely
into directories. A module reaches only what it is granted an import for, so
adding a dependency that crosses a boundary is a compile error rather than
something a reviewer has to notice.

| Module | Holds | May import |
| --- | --- | --- |
| `tables` | generated Unicode data | nothing |
| `encoding` | UTF-8 stepping, scalar plus its record | `tables` |
| `segmentation` | grapheme clusters, word bounds | `tables`, `encoding` |
| `linebreak` | UAX #14 opportunities and its machine | `tables`, `encoding` |
| `normalization` | NFC and NFD | `tables`, `encoding` |
| `layout` | width, scanning, wrapping | all of the above |
| `zunic` | `root.zig` and the text view | all of the above |

Only `zunic` is public. The internal modules are created rather than named
in the build graph, so a dependent cannot reach past the facade to one of
them.

The graph is acyclic and points away from `tables`. Two consequences worth
knowing: `linebreak`'s state machine is private to that module, and an
engine cannot quietly start depending on `layout`, which is the module that
fuses the others.

`-Dnormalization-buffer-bytes` is compiled into `normalization`, so a target
that needs a different setting gets its own instance of the whole graph
rather than sharing one.

## Look up related properties together

[properties.zig](../src/tables/properties.zig) stores grapheme, width, and line-break
facts together in a packed record. Repeated blocks of records are stored once.
The scanner can look up one record and reuse its fields for all three tasks.
ASCII can skip UTF-8 decoding and use direct array access.

Word and normalization data have their own generated tables because they need
different facts. Generators and their pinned input data live under
[`src/tools/`](../src/tools/). Generated Zig files are checked in, so ordinary
users need neither Python nor a Unicode-data download to build the library.

## Use tables where they remove repeated rule work

Grapheme and word decisions are compiled from Zig rule functions at compile
time. Line-break decisions are compiled ahead of time by a Python generator.
These are different generation paths; all produce data used by the runtime
loops. The per-operation implementation pages explain what each table replaces
and how the result is checked.

## Build options

The package requires Zig 0.16.0 or later according to `build.zig.zon`.

| Option | Default | Effect |
| --- | --- | --- |
| `-Dwrap-fast-path=off|scalar|auto|simd` | `auto` | Selects ASCII detection for wrapping and width. Forced SIMD requires aarch64 or x86_64. |
| `-Dnormalization-buffer-bytes=N` | `128` | Inline normalization run buffer; positive multiple of 32. See the [run limit](normalization/README.md#combining-run-limit). |
| `-Doptimize=Debug|ReleaseSafe|ReleaseFast|ReleaseSmall` | Zig's standard default | Standard Zig optimization mode. |

Applications pass dependency options through `b.dependency`, for example:

```zig
const dep = b.dependency("zunic", .{
    .target = target,
    .optimize = optimize,
    .@"normalization-buffer-bytes" = @as(usize, 256),
});
app.root_module.addImport("zunic", dep.module("zunic"));
```

Here `b`, `target`, `optimize`, and `app` are supplied by the application's
build file. The old `line-break-engine` option has been removed.

## Check behavior as well as speed

`zig build test` runs the main tests, including pinned Unicode fixtures and
the documentation examples. More focused commands are:

```sh
zig build docs-test
zig build line-break-tests
zig build wrap-regressions
zig build wrap-exhaustive
```

Fixtures check published examples of the Unicode rules. Reference comparisons
check that shortcuts preserve the rule implementation. Instrumented tests count
decodes and buffered tokens to catch excessive repeated work. None alone proves
correctness for every input; the known line-break issue is documented under
[wrapping](wrap/implementation.md#known-limitation).

Benchmark results depend on the compiler, CPU, inputs, and Unicode versions.
These pages explain the design without treating a measurement from one run as
a permanent speed guarantee.
