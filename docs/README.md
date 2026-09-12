# Zunic documentation

Zunic has two basic exports for working with Unicode: **`cp` and `text`**.

- Use [`zunic.cp(value)`](codepoint/README.md) if you have a codepoint stored
  as a `u21` and want its Unicode properties, isolated display width, or
  case-folded values.
- Use [`zunic.text(bytes)`](text/README.md) if you have UTF-8 text in a
  `[]const u8` and want to iterate codepoints, graphemes, or words, measure
  display width, wrap lines, trim whitespace, or normalize text.

Neither constructor allocates or validates its input. `cp()` holds the numeric
value; `text()` borrows the existing byte slice without copying or scanning it.
Unicode data is pinned to **17.0.0**, available as `zunic.unicode_version`.

## API overview

```zig
pub fn cp(value: u21) CodepointView;
pub fn text(bytes: []const u8) Text;
```

### Codepoint

```zig
const point = zunic.cp(0x1f600); // 😀
std.debug.print("Emoji presentation: {}\n", .{point.terminal().isEmojiPresentation});
// Emoji presentation: true
```

The [codepoint documentation](codepoint/README.md) covers property groups,
width, whitespace, case folding, and the handling of arbitrary `u21` values.

### Text

```zig
const view = zunic.text("Hello, 世界!");
std.debug.print("Columns: {d}\n", .{view.width()});
// Columns: 12
```

The [text documentation](text/README.md) helps you choose an operation and
links to its signatures, examples, results, and error behavior.
`text(bytes)` does not check UTF-8 in advance; use
[`validate()`](text/README.md#entry-point-and-validation) if you want to pay
for that check before processing. Individual methods handle malformed input
according to their own contracts.

The two entry points work together: [codepoint iteration](text/codepoints/README.md)
decodes UTF-8 and returns the same `CodepointView` that `cp(value)` constructs.
You can call its property methods directly.

## Shared conventions and examples

Read [shared conventions](conventions.md) for input lifetimes, iterator
copying, byte offsets, and display columns.

Examples omit imports for brevity. They assume `const zunic = @import("zunic");`
and `const std = @import("std");` in a module that imports the Zunic dependency.
[examples.zig](examples.zig) contains executable documentation tests covering
the APIs; it is not a copy of every example on these pages. Run them with
`zig build docs-test` or as part of `zig build test` from the repository root.

## Lower-level APIs and implementation

For codepoint-at-a-time segmentation, see
[incremental grapheme boundaries](codepoint/grapheme-break.md).
The exported [`utf8`](../src/encoding/utf8.zig),
[`line_break`](../src/linebreak/linebreak.zig), and
[`testing`](../src/root.zig) namespaces support custom scanners and
work-bound tests; their source comments describe those interfaces.

[Architecture](internals/README.md) covers module dependencies, property data,
build options, and verification. Each operation's implementation page explains
its algorithms and optimizations. Private engine types and table layouts are
not public API promises.
