# Internal Zig modules

[Implementation overview](README.md) · [Public API](../README.md)

The library is split into Zig modules declared in `build.zig`, not merely
into directories. A module reaches only what it is granted an import for, so
adding a dependency that crosses a boundary is a compile error rather than
something a reviewer has to notice.

| Module | Holds | May import |
| --- | --- | --- |
| `tables` | generated Unicode data | nothing |
| `types` | shared byte positions, spans, and display measurements | nothing |
| `encoding` | UTF-8 stepping, scalar plus its record, whole-slice ASCII check | `tables` |
| `segmentation` | grapheme clusters, word bounds | `tables`, `encoding` |
| `linebreak` | UAX #14 opportunities and its machine | `tables`, `encoding` |
| `normalization` | NFC and NFD | `tables`, `encoding` |
| `layout` | width, scanning, wrapping | `tables`, `encoding`, `segmentation`, `linebreak` |
| `zunic` | `root.zig` and the text view | all of the above |

Only `zunic` is public. The internal modules are created rather than named
in the build graph, so a dependent cannot reach past the facade to one of
them.

The graph is acyclic, with `tables` and `types` as independent foundations. Two consequences worth
knowing: `linebreak`'s state machine is private to that module, and an
engine cannot quietly start depending on `layout`, which is the module that
fuses the others.

The text view uses the shared `Span` and `ByteOffset` definitions from
`src/types.zig` rather than defining copies in the public facade.

The normalization and layout modules also receive generated build options.
`-Dnormalization-buffer-bytes` is compiled into `normalization`, so a target
that needs a different setting gets its own instance of the whole graph
rather than sharing one.
