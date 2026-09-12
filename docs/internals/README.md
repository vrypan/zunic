# Implementation overview

[Documentation index](../README.md)

## Public views and internal modules

Applications import `zunic` and open a borrowed [`Text`](../text/README.md)
view with `zunic.text(bytes)`. The text view lives in the internal `text` module, while individual code-point
views live in `cp`. The public facade re-exports their APIs; Unicode engines
and tables have their own internal build modules.

## Borrow bytes and return positions

Most public operations answer questions about the original text. They return
byte positions and column counts instead of allocating substrings. Views cost
only a slice and options; iterators hold their own progress. Callers choose
whether to keep results, render them, or stop early.

Normalization may reorder, expand, or combine input characters. It returns
scalar values or writes UTF-8 into a caller's buffer instead of returning
positions.

## Internal modules

The [module graph](modules.md) describes the build dependencies and how they
are enforced. These are implementation details; applications import `zunic`.

## Look up related properties together

[properties.zig](../../src/tables/properties.zig) stores grapheme, width, and line-break
facts together in a packed record. Repeated blocks of records are stored once.
The scanner can look up one record and reuse its fields for all three tasks.
ASCII can skip UTF-8 decoding and use direct array access.

Word and normalization data have their own generated tables because they need
different facts. Generators and their pinned input data live under
[`src/tools/`](../../src/tools). Generated Zig files are checked in, so ordinary
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
| `-Dnormalization-buffer-bytes=N` | `128` | Inline normalization run buffer; positive multiple of 32. See the [run limit](../text/normalization/README.md#combining-run-limit). |
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
zig build test-cp
zig build test-text
zig build test-segmentation
zig build test-api
zig build docs-test
zig build line-break-tests
zig build wrap-regressions
zig build wrap-exhaustive
```

Fixtures check published examples of the Unicode rules. Reference comparisons
check that shortcuts preserve the rule implementation. Instrumented tests count
decodes and buffered tokens to catch excessive repeated work. None alone proves
correctness for every input; the known line-break issue is documented under
[wrapping](../text/wrap/implementation.md#known-limitation).

Benchmark results depend on the compiler, CPU, inputs, and Unicode versions.
These pages explain the design without treating a measurement from one run as
a permanent speed guarantee.

`test-cp` runs scalar property and case-folding checks directly against `cp`.
`test-text` runs text iteration, trimming, and ASCII checks using internal
modules. `test-segmentation` includes streaming fixture and replay checks.
`test-api` keeps public construction, type integration, and documentation
examples. Existing focused targets remain available; the aggregate `test`
reuses each test artifact once. The two new targets are Zig-only; the existing
`test-unicode-properties` and `test-case-folding` targets retain their additional
generated-data verification commands.
