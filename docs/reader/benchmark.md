# Reader benchmarks

Run the checked Reader benchmark with:

```sh
zig build benchmark-reader -Doptimize=ReleaseFast
```

The executable is also installed as `zig-out/bin/zunic-reader-benchmark`.
It emits CSV samples for three corpora: ASCII with CR/LF, multilingual text
with emoji, and combining-mark-heavy text. Modes are:

| Mode | Iterator | Input |
| --- | --- | --- |
| 0 | Codepoints | Fixed Reader |
| 1 | Grapheme updates | Fixed Reader |
| 2 | Codepoints | One-byte refills, four-byte buffer |
| 3 | Grapheme updates | One-byte refills, four-byte buffer |

Before timing, each mode checks scalar, boundary, and final-event counts and
a checksum against independently decoded slice iteration. The grapheme
checksum consumes both span offsets and both flags. All cases warm up, then
run eight samples with rotating case order. Fixed cases use 2,000 iterations
per sample; refill cases use 500. Normalize elapsed time by iterations when
comparing modes. This measures iteration CPU cost, not file-system latency.
Unicode fixture tests provide exact boundary checks beyond these corpus checks.
