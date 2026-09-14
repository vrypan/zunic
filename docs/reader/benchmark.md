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

## Decoder optimization results

Measured on 2026-09-14, native macOS ARM64, Zig 0.16.0, ReleaseFast. The same
harness was compiled against the decoder at `fc26fd6` and against fused
incremental decoding with an inlined `next()`. Three process runs alternated
the before/after order, giving 24 samples per case. The figures below divide
the median baseline time by the median optimized time; larger is faster.

| Corpus | Fixed codepoints | Fixed graphemes | Refill codepoints | Refill graphemes |
| --- | ---: | ---: | ---: | ---: |
| ASCII | 1.40× | 2.01× | 1.25× | 1.14× |
| Multilingual | 2.69× | 2.10× | 1.35× | 1.23× |
| Combining marks | 2.01× | 1.69× | 1.28× | 1.10× |

These are local measurements, not portable performance guarantees or CI
thresholds. Compared with the baseline benchmark, the optimized Mach-O
`__text` section grew by 1,024 bytes and `__TEXT,__const` by 64 bytes.
Unicode table definitions and sizes did not change.

A small inline ASCII wrapper around an out-of-line decoder was also tested;
full inlining performed better across these corpora. Three table-free ASCII
grapheme-classification variants showed no consistent benefit, with some
regressions, and were discarded. The existing generated property lookup
remains in use; no additional ASCII table is retained by this change.

Verification included the full Debug and ReleaseFast suites (259 passed,
one optional test skipped in each), exhaustive scalar roundtrips, malformed
prefix/error-precedence tests, and every Unicode grapheme fixture with
one- to four-byte refills across four- to eight-byte buffers.
