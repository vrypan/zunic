# Latest benchmark timings

These results cover the runtime library code in **Zunic v0.6.0**. Measurements
preceded the version-metadata bump in commit `62ffe0e`; the measured package
metadata still declared 0.5.0. That commit changes release metadata and
documentation only, so it does not change the measured runtime code.

The seventeen non-UTF-8 operations are recorded from
`benchmarks/20261005T113605Z-zig017-5f95f7c-ae1079/summary.json` on 2026-10-05.
The measured Zunic tree was clean at commit `5f95f7c`.
The uucode revision was `cba2b5bc9f79d200541a7f4fdd62a1ba5ca5f166` (0.2.0 with Zig 0.17
compatibility). Both peers used Unicode 17.0.0 and Zig 0.17.0, ReleaseFast,
and the native CPU target on Apple M4 ARM64, macOS 27.0.1.

Each table value is the median of three run medians. Runs used three
alternating peer pairs and 15 calibrated samples per executable and corpus.
The full run included all 18 operations and nine corpora. Its recorded executable
sizes were 1,470,872 bytes for Zunic and 1,520,096 bytes for uucode.
These executables include the adapters, timing harness, embedded corpora, and
used tables; their sizes are not standalone library-size measurements.

`make test` passed both peer-adapter tests and the CLI, filtered-operation,
exact-dump, and operation-contract checks. During benchmarking, every timed
count and checksum agreed with its peer's dump. Exact output records and
corpus hashes were unchanged before and after all six timed runs.

The UTF-8 section below supersedes the full run’s decoder-loop measurements
with a focused rerun of the public codepoint iterator. The other sections
retain their full-run measurements.

## UTF-8 decoding

Source: `benchmarks/20261005T134156Z-zig017-public-codepoints-8be596/summary.json`, recorded on
2026-10-05 from the working tree based on `5f95f7c`, with the UTF-8 adapter
changed to `text(bytes).codepoints().iterator()`. The runtime library was
unchanged. Source hashes in this archive identify the uncommitted adapter.
The compiler, CPU target, optimization mode, uucode revision, and corpus
hashes match the full run above. This focused rerun used three alternating
pairs and 15 samples per executable and corpus; all nine outputs matched.
The executable sizes for this rerun were 1,470,984 bytes for Zunic and
1,520,096 bytes for uucode.

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 18.821 | 40.727 | 2.16× | 27647/27647 | same |
| hindi | 20.723 | 37.059 | 1.79× | 19595/19595 | same |
| korean | 22.617 | 35.885 | 1.59× | 21191/21191 | same |
| russian | 19.533 | 38.523 | 1.97× | 28552/28552 | same |
| source_code | 17.531 | 27.141 | 1.55× | 50202/50202 | same |
| english | 18.686 | 28.442 | 1.52× | 49489/49489 | same |
| japanese | 23.969 | 31.678 | 1.32× | 18108/18108 | same |
| mandarin | 23.347 | 30.209 | 1.29× | 17639/17639 | same |
| features | 0.055 | 0.111 | 2.02× | 75/75 | same |

## Extended grapheme ranges

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 42.924 | 78.272 | 1.82× | 27383/27383 | same |
| hindi | 32.115 | 58.688 | 1.83× | 12642/12642 | same |
| korean | 41.948 | 50.988 | 1.22× | 21191/21191 | same |
| russian | 41.241 | 62.659 | 1.52× | 28544/28544 | same |
| source_code | 52.011 | 65.289 | 1.26× | 50202/50202 | same |
| english | 52.701 | 69.722 | 1.32× | 49472/49472 | same |
| japanese | 33.064 | 49.714 | 1.50× | 18045/18045 | same |
| mandarin | 31.344 | 42.958 | 1.37× | 17639/17639 | same |
| features | 0.117 | 0.200 | 1.71× | 64/65 | diff |

## Grapheme ranges with cluster width

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 92.819 | 145.728 | 1.57× | 27383/27383 | same |
| hindi | 67.249 | 115.614 | 1.72× | 12642/12642 | diff |
| korean | 80.077 | 114.819 | 1.43× | 21191/21191 | same |
| russian | 91.987 | 145.569 | 1.58× | 28544/28544 | same |
| source_code | 112.678 | 219.123 | 1.94× | 50202/50202 | same |
| english | 104.206 | 201.523 | 1.93× | 49472/49472 | same |
| japanese | 59.014 | 88.673 | 1.50× | 18045/18045 | same |
| mandarin | 57.715 | 83.255 | 1.44× | 17639/17639 | same |
| features | 0.231 | 0.376 | 1.63× | 64/65 | diff |

## Whole-text grapheme width

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 90.820 | 143.143 | 1.58× | 27275/27275 | same |
| hindi | 58.757 | 114.352 | 1.95× | 15702/16480 | diff |
| korean | 73.710 | 114.858 | 1.56× | 35376/35376 | same |
| russian | 89.525 | 143.620 | 1.60× | 28389/28389 | same |
| source_code | 1.801 | 176.325 | 97.90× | 48517/48517 | same |
| english | 3.192 | 175.672 | 55.04× | 49223/49223 | same |
| japanese | 58.051 | 87.097 | 1.50× | 33966/33966 | same |
| mandarin | 56.761 | 82.396 | 1.45× | 33576/33576 | same |
| features | 0.232 | 0.380 | 1.64× | 64/66 | diff |

## Unicode terminal property facts

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 51.077 | 78.803 | 1.54× | 27647/27647 | same |
| hindi | 44.948 | 62.142 | 1.38× | 19595/19595 | same |
| korean | 42.655 | 60.315 | 1.41× | 21191/21191 | same |
| russian | 51.332 | 77.160 | 1.50× | 28552/28552 | same |
| source_code | 67.167 | 91.422 | 1.36× | 50202/50202 | same |
| english | 68.714 | 93.589 | 1.36× | 49489/49489 | same |
| japanese | 40.117 | 60.252 | 1.50× | 18108/18108 | same |
| mandarin | 38.479 | 58.864 | 1.53× | 17639/17639 | same |
| features | 0.134 | 0.206 | 1.54× | 75/75 | same |

## Fused scalar terminal-property lookup

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 29.203 | 39.559 | 1.35× | 27647/27647 | same |
| hindi | 20.613 | 27.794 | 1.35× | 19595/19595 | same |
| korean | 22.398 | 31.013 | 1.38× | 21191/21191 | same |
| russian | 29.746 | 40.964 | 1.38× | 28552/28552 | same |
| source_code | 48.749 | 65.385 | 1.34× | 50202/50202 | same |
| english | 49.452 | 66.161 | 1.34× | 49489/49489 | same |
| japanese | 18.878 | 26.472 | 1.40× | 18108/18108 | same |
| mandarin | 18.535 | 25.944 | 1.40× | 17639/17639 | same |
| features | 0.084 | 0.119 | 1.42× | 75/75 | same |

## Full default case folding

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 54.303 | 68.162 | 1.26× | 27647/27647 | same |
| hindi | 47.456 | 55.481 | 1.17× | 19595/19595 | same |
| korean | 43.805 | 52.603 | 1.20× | 21191/21191 | same |
| russian | 53.266 | 67.337 | 1.26× | 28552/28552 | same |
| source_code | 52.421 | 73.717 | 1.41× | 50202/50202 | same |
| english | 52.093 | 74.285 | 1.43× | 49489/49489 | same |
| japanese | 34.664 | 45.293 | 1.31× | 18108/18108 | same |
| mandarin | 33.709 | 43.226 | 1.28× | 17639/17639 | same |
| features | 0.127 | 0.164 | 1.29× | 75/75 | same |

## Simple uppercase mapping

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 11.183 | 11.952 | 1.07× | 27647/27647 | same |
| hindi | 8.090 | 9.335 | 1.15× | 19595/19595 | same |
| korean | 8.885 | 11.561 | 1.30× | 21191/21191 | same |
| russian | 11.678 | 15.833 | 1.36× | 28552/28552 | same |
| source_code | 20.442 | 20.851 | 1.02× | 50202/50202 | same |
| english | 20.231 | 23.957 | 1.18× | 49489/49489 | same |
| japanese | 7.531 | 9.904 | 1.32× | 18108/18108 | same |
| mandarin | 7.451 | 9.558 | 1.28× | 17639/17639 | same |
| features | 0.030 | 0.046 | 1.53× | 75/75 | same |

## Simple lowercase mapping

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 11.180 | 12.095 | 1.08× | 27647/27647 | same |
| hindi | 8.040 | 8.890 | 1.11× | 19595/19595 | same |
| korean | 9.072 | 11.459 | 1.26× | 21191/21191 | same |
| russian | 12.234 | 15.845 | 1.30× | 28552/28552 | same |
| source_code | 20.479 | 22.224 | 1.09× | 50202/50202 | same |
| english | 21.010 | 24.950 | 1.19× | 49489/49489 | same |
| japanese | 7.573 | 9.463 | 1.25× | 18108/18108 | same |
| mandarin | 7.538 | 7.956 | 1.06× | 17639/17639 | same |
| features | 0.031 | 0.046 | 1.48× | 75/75 | same |

## Simple titlecase mapping

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 11.170 | 11.950 | 1.07× | 27647/27647 | same |
| hindi | 8.108 | 9.254 | 1.14× | 19595/19595 | same |
| korean | 8.869 | 11.552 | 1.30× | 21191/21191 | same |
| russian | 11.629 | 15.819 | 1.36× | 28552/28552 | same |
| source_code | 20.408 | 20.856 | 1.02× | 50202/50202 | same |
| english | 20.192 | 24.082 | 1.19× | 49489/49489 | same |
| japanese | 7.533 | 9.882 | 1.31× | 18108/18108 | same |
| mandarin | 7.502 | 9.622 | 1.28× | 17639/17639 | same |
| features | 0.031 | 0.046 | 1.48× | 75/75 | same |

## Exact numeric properties

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 13.811 | 28.910 | 2.09× | 27647/27647 | same |
| hindi | 10.305 | 21.761 | 2.11× | 19595/19595 | same |
| korean | 11.875 | 24.251 | 2.04× | 21191/21191 | same |
| russian | 16.102 | 33.988 | 2.11× | 28552/28552 | same |
| source_code | 26.048 | 53.947 | 2.07× | 50202/50202 | same |
| english | 27.812 | 55.875 | 2.01× | 49489/49489 | same |
| japanese | 10.073 | 20.519 | 2.04× | 18108/18108 | same |
| mandarin | 9.803 | 20.273 | 2.07× | 17639/17639 | same |
| features | 0.040 | 0.091 | 2.27× | 75/75 | same |

## Primary Script property

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 9.912 | 10.034 | 1.01× | 27647/27647 | same |
| hindi | 6.945 | 7.098 | 1.02× | 19595/19595 | same |
| korean | 7.575 | 7.689 | 1.02× | 21191/21191 | same |
| russian | 10.115 | 10.376 | 1.03× | 28552/28552 | same |
| source_code | 17.985 | 17.554 | 0.98× | 50202/50202 | same |
| english | 17.873 | 17.816 | 1.00× | 49489/49489 | same |
| japanese | 6.435 | 6.558 | 1.02× | 18108/18108 | same |
| mandarin | 6.268 | 6.405 | 1.02× | 17639/17639 | same |
| features | 0.028 | 0.031 | 1.11× | 75/75 | same |

## Bidirectional scalar properties

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 14.836 | 18.948 | 1.28× | 27647/27647 | same |
| hindi | 10.471 | 13.907 | 1.33× | 19595/19595 | same |
| korean | 11.324 | 15.800 | 1.40× | 21191/21191 | same |
| russian | 15.281 | 21.286 | 1.39× | 28552/28552 | same |
| source_code | 26.964 | 36.378 | 1.35× | 50202/50202 | same |
| english | 26.972 | 36.111 | 1.34× | 49489/49489 | same |
| japanese | 9.657 | 14.332 | 1.48× | 18108/18108 | same |
| mandarin | 9.413 | 13.193 | 1.40× | 17639/17639 | same |
| features | 0.042 | 0.056 | 1.33× | 75/75 | same |

## Bidirectional scalar mappings

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 30.654 | 35.859 | 1.17× | 27647/27647 | same |
| hindi | 22.544 | 26.474 | 1.17× | 19595/19595 | same |
| korean | 25.106 | 29.882 | 1.19× | 21191/21191 | same |
| russian | 33.930 | 40.051 | 1.18× | 28552/28552 | same |
| source_code | 60.476 | 75.274 | 1.24× | 50202/50202 | same |
| english | 58.780 | 67.650 | 1.15× | 49489/49489 | same |
| japanese | 21.328 | 28.973 | 1.36× | 18108/18108 | same |
| mandarin | 20.987 | 25.218 | 1.20× | 17639/17639 | same |
| features | 0.081 | 0.109 | 1.35× | 75/75 | same |

## Canonical combining class

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 10.947 | 11.529 | 1.05× | 27647/27647 | same |
| hindi | 7.243 | 8.092 | 1.12× | 19595/19595 | same |
| korean | 7.733 | 7.399 | 0.96× | 21191/21191 | same |
| russian | 10.491 | 10.607 | 1.01× | 28552/28552 | same |
| source_code | 18.540 | 17.267 | 0.93× | 50202/50202 | same |
| english | 18.449 | 17.442 | 0.95× | 49489/49489 | same |
| japanese | 6.794 | 7.243 | 1.07× | 18108/18108 | same |
| mandarin | 6.437 | 6.495 | 1.01× | 17639/17639 | same |
| features | 0.029 | 0.036 | 1.24× | 75/75 | same |

## Immediate decomposition facts

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 18.298 | 22.693 | 1.24× | 27647/27647 | same |
| hindi | 8.241 | 8.623 | 1.05× | 19595/19595 | same |
| korean | 9.652 | 12.592 | 1.30× | 21191/21191 | same |
| russian | 16.688 | 22.287 | 1.34× | 28552/28552 | same |
| source_code | 21.826 | 21.854 | 1.00× | 50202/50202 | same |
| english | 21.789 | 22.472 | 1.03× | 49489/49489 | same |
| japanese | 11.084 | 14.008 | 1.26× | 18108/18108 | same |
| mandarin | 9.856 | 12.564 | 1.27× | 17639/17639 | same |
| features | 0.047 | 0.056 | 1.19× | 75/75 | same |

## Incremental grapheme boundaries

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 64.872 | 176.390 | 2.72× | 27646/27646 | same |
| hindi | 50.137 | 164.205 | 3.28× | 19594/19594 | same |
| korean | 51.550 | 190.807 | 3.70× | 21190/21190 | same |
| russian | 61.797 | 178.177 | 2.88× | 28551/28551 | same |
| source_code | 121.908 | 234.605 | 1.92× | 50201/50201 | same |
| english | 88.795 | 242.133 | 2.73× | 49488/49488 | same |
| japanese | 43.684 | 107.658 | 2.46× | 18107/18107 | same |
| mandarin | 42.715 | 104.443 | 2.45× | 17638/17638 | same |
| features | 0.152 | 0.445 | 2.93× | 74/74 | diff |

## Ghostty scalar-width composition

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 45.375 | 53.135 | 1.17× | 27647/27647 | same |
| hindi | 35.134 | 45.251 | 1.29× | 19595/19595 | same |
| korean | 38.785 | 47.085 | 1.21× | 21191/21191 | same |
| russian | 46.020 | 51.792 | 1.13× | 28552/28552 | same |
| source_code | 51.457 | 66.567 | 1.29× | 50202/50202 | same |
| english | 41.944 | 53.029 | 1.26× | 49489/49489 | same |
| japanese | 31.581 | 48.041 | 1.52× | 18108/18108 | same |
| mandarin | 30.463 | 46.839 | 1.54× | 17639/17639 | same |
| features | 0.121 | 0.137 | 1.13× | 75/75 | same |

Ratio = uucode time / Zunic time; above 1 means Zunic took less time.
Exact output records are compared before and after timing; differences are reported rather than treated as benchmark failures.
Inputs are valid UTF-8 and file I/O is outside timing.
The UTF-8 row traverses Zunic `text(bytes).codepoints().iterator()` and uucode `utf8.Iterator`, consuming every scalar value and ending byte offset.
Measured traversal consumes each grapheme's start, end, and width; Zunic's renderable flag has no uucode counterpart and is excluded.
Both peers use Unicode 17.0.0; whole-grapheme width policies can still differ and are shown explicitly.
Terminal-property, case-mapping, numeric, Script, normalization-fact, full-fold, and Ghostty-width rows agree exactly on these valid UTF-8 corpora.
The fused scalar lookup row receives predecoded code points, excluding UTF-8 decoding from its timing.
Simple case, numeric, Script, bidi, combining-class, and decomposition rows also receive predecoded code points.
uucode exposes non-decimal numeric values as text; its numeric row includes parsing and reducing that text to Zunic's exact rational result.
Multi-result operations use independent field accumulators, combined once after traversal, to reduce checksum dependency-chain cost.
The focused streaming row intentionally records uucode's emoji-modifier tailoring against Zunic's default UAX #29 GB9 behavior.
