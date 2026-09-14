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
| 1 | Track grapheme positions | Fixed Reader |
| 2 | Codepoints | One-byte refills, four-byte buffer |
| 3 | Track grapheme positions | One-byte refills, four-byte buffer |
| 4 | Accumulate grapheme bytes and track positions | Fixed Reader |
| 5 | Accumulate grapheme bytes and track positions | One-byte refills, four-byte buffer |
| 6 | Accumulate grapheme bytes and flags only | Fixed Reader |
| 7 | Accumulate grapheme bytes and flags only | One-byte refills, four-byte buffer |
| 8 | Accumulate bytes with incremental measurement | Fixed Reader |
| 9 | Accumulate bytes with incremental measurement | One-byte refills, four-byte buffer |
| 10 | Accumulate bytes and remeasure each prefix with Text | Fixed Reader |
| 11 | Accumulate bytes and remeasure each prefix with Text | One-byte refills, four-byte buffer |

Before timing, each mode checks scalar, boundary, and final-event counts and
a checksum against independently decoded slice iteration. Byte reconstruction
is also checked exactly against the original input. The position checksum
consumes consumer-tracked offsets and both flags; modes 4 through 11 copy bytes into
a consumer buffer and checksum each finalized grapheme. They use a fixed
4,096-byte buffer sufficient for these corpora, not a library cluster limit.
All cases warm up, then run eight samples with rotating case order.
Fixed cases use 2,000 iterations
per sample; refill cases use 500. Normalize elapsed time by iterations when
comparing modes. This measures iteration CPU cost, not file-system latency.
Unicode fixture tests provide exact boundary checks beyond these corpus checks.
Modes 6 and 7 consume bytes and flags without tracking positions.
Modes 8 through 11 also consume cumulative columns and renderability after
every update, including EOF. Their expected checksum uses the slice API for
each successive prefix outside timing. On revisions without `.measured()`,
modes 8 and 9 fall back to remeasuring, allowing the same harness to compile.

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
thresholds. These historical results used the original four-mode harness,
whose grapheme checksum also consumed scalar values. Compared with the
baseline benchmark, the optimized Mach-O
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

## Owned-byte update experiment

The six-mode version of this harness was compiled against three versions on native
macOS ARM64 with Zig 0.16.0, ReleaseFast:

- Baseline: `9e5f046`, returning codepoints, with consumer UTF-8 re-encoding.
- Control: the baseline with the grapheme iterator's `next()` explicitly inlined.
- Byte API: the inlined iterator returning owned UTF-8 bytes captured by the
  shared decoder before advancing the Reader.

After discarding measurements affected by high system load, six runs of each
unchanged binary rotated and reversed execution order. Each case has 48 timing
samples. The table shows throughput ratios from median times for byte
accumulation; a value above 1 is faster.

| Corpus | Fixed vs baseline | Refills vs baseline | Fixed vs inline control | Refills vs inline control |
| --- | ---: | ---: | ---: | ---: |
| ASCII | 1.26× | 1.11× | 1.00× | 1.04× |
| Multilingual | 1.32× | 1.12× | 1.17× | 1.03× |
| Combining marks | 1.42× | 1.16× | 1.20× | 1.08× |

Span-only traversal was within about 2% of the inline control. Codepoint-only
iteration remained within about 2%, with byte capture removed at compile time.
The measurements support retaining the byte API for text consumers, but part
of the improvement over the baseline comes from inlining, not byte capture.
No Unicode tables were added or enlarged.

On this target the update shrank from 32 to 24 bytes. The grapheme iterator
remains 56 bytes and the codepoint iterator remains 24 bytes. The final
benchmark has the same section sizes as the measured prototype.

After the successful comparison, examples and tests were migrated to
`update.bytes()`. Full Debug and ReleaseFast suites each passed 261 tests
with one optional skip. Coverage includes all valid scalar encodings,
updates retained across buffer reuse, Unicode boundary fixtures across
refills, and unchanged malformed-input and offset-overflow behavior.

## Removing spans from updates

The final API returns only owned bytes and boundary flags. Removing the span
and duplicate position bookkeeping reduces the native update from 24 to
7 bytes and the grapheme iterator from 56 to 40 bytes. The codepoint iterator
remains 24 bytes, including its checked input offset.

Four alternating runs of the eight-mode harness compared the owned-byte API
with and without spans on the same macOS ARM64/Zig 0.16.0 setup. Each case has
32 samples. Byte accumulation without positions (modes 6 and 7) improved:

| Corpus | Fixed Reader throughput ratio | One-byte refill throughput ratio |
| --- | ---: | ---: |
| ASCII | 1.01× | 1.10× |
| Multilingual | 1.02× | 1.11× |
| Combining marks | 1.03× | 1.11× |

This is a tradeoff for consumers needing source positions. Tracking offsets
in the consumer reduced fixed-Reader throughput by about 7–17% in mode 1,
and by about 1–12% when combined with byte accumulation in mode 4. Refill
position workloads were roughly unchanged or modestly faster. Keeping only
bytes and flags favors consumers that accumulate or display text without
source positions; the API documentation explains how to track them when needed.

## Incremental Reader measurement

Four alternating runs on native macOS ARM64 with Zig 0.16.0/ReleaseFast
collected 32 samples per case. Modes 8 and 9 accumulate the same bytes as
unmeasured modes 6 and 7, adding cumulative width and renderability to the
checksum after every update. Modes 10 and 11 instead recompute that measurement
by passing the accumulated current grapheme to the slice API each time.

| Corpus | Fixed measured/unmeasured time | Refill measured/unmeasured time | Fixed speedup over remeasuring | Refill speedup over remeasuring |
| --- | ---: | ---: | ---: | ---: |
| ASCII | 1.26× | 1.11× | 1.19× | 1.11× |
| Multilingual | 1.23× | 1.10× | 1.51× | 1.22× |
| Combining marks | 1.32× | 1.09× | 1.99× | 1.41× |

The first two columns are additional workflow cost; lower is better. The last
two are throughput improvements over repeated slice measurement; higher is
better. They include consumption of the measurement fields, not just property
lookup time. Longer graphemes benefit from avoiding repeated prefix scans.

Separate before/after builds of the unchanged eight-mode harness checked the
unmeasured path: byte-accumulation throughput stayed within about 3% on fixed
Readers and about 2% with refills. Its iterator remains 40 bytes and updates
remain 7 bytes on this target. The measured iterator is 56 bytes and updates
are 9 bytes. Measurement shares the existing compact grapheme/width record;
no Unicode tables were added or enlarged.

Full Debug and ReleaseFast suites each passed 267 tests with one optional
skip. Every grapheme fixture is checked at successive prefixes in both modes,
with fixed Readers and varied short refills. Other checks cover decreasing
width, renderability, owned bytes, sticky errors, no lookahead, offset overflow,
and bounded measurement of long clusters. Selecting measurement after an
unmeasured update was also verified to panic in ReleaseFast.
