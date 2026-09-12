# Incremental grapheme boundaries

[Documentation index](../README.md) · [Codepoints](README.md) · [Source](../../src/segmentation/grapheme_stream.zig)

Use `zunic.graphemeBreak(previous, current, &state)` if you receive codepoints
one at a time and need to detect grapheme boundaries. If you have UTF-8 bytes,
[text grapheme iteration](../text/graphemes/README.md) handles decoding and
returns complete cluster spans.

## API

```zig
pub const GraphemeState = struct { /* copyable checkpoint state */ };
pub fn graphemeBreak(previous: u21, current: u21, state: *GraphemeState) bool;
```

Initialize `GraphemeState` with `.{};` and call `graphemeBreak()` for each
adjacent pair. A `true` result means there is a boundary before `current`.
The call updates the state, leaving it ready for the next pair even when a
new cluster begins.

The first call seeds the state from `previous`. Later calls pass the prior
`current` as `previous` again; the state does not consume it twice.

```zig
var state: zunic.GraphemeState = .{};
std.debug.print("Boundary before accent: {}\n", .{zunic.graphemeBreak('e', 0x0301, &state)});
std.debug.print("Boundary before x: {}\n", .{zunic.graphemeBreak(0x0301, 'x', &state)});
// Boundary before accent: false
// Boundary before x: true
```

Keep the state across pairs: a boundary decision can depend on earlier
codepoints in the cluster. Copy it to checkpoint speculative input, and
restore the copy to undo that input. Start with a fresh state for an
independent sequence.

This applies the default Unicode grapheme rules, including their behavior
for controls. Values above `zunic.max_codepoint` form independent boundaries
and clear carried context. Surrogates use the default `.other` classification;
this API does not validate Unicode scalar values or decode UTF-8.
