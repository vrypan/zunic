# zunic

Allocation-free Unicode primitives for Zig terminal applications.

The package currently provides tolerant UTF-8 stepping, Unicode 16.0.0
extended-grapheme segmentation, and a terminal cell-width policy. Its grapheme
implementation passes the official Unicode 16.0.0 `GraphemeBreakTest` fixture.

```sh
zig build test
```

Use `src/root.zig` as the `zunic` module root.
