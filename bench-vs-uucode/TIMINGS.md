# Latest benchmark timings

Recorded from `benchmarks/20260912T180222Z-uucode-fddbcc/summary.json` on 2026-09-12 at Zunic commit `d82ae3d`. The benchmark used Zig 0.16.0, ReleaseFast, and the native CPU target on macOS 26.6.2 ARM64.

Label: `uucode`. Sequential alternating pairs: 3.

Unicode: Zunic 17.0.0; uucode 17.0.0.

## UTF-8 decoding

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 33.133 | 56.041 | 1.69× | 27647/27647 | same |
| hindi | 26.878 | 52.392 | 1.95× | 19595/19595 | same |
| korean | 32.703 | 48.473 | 1.48× | 21191/21191 | same |
| russian | 32.453 | 54.285 | 1.67× | 28552/28552 | same |
| source_code | 25.986 | 61.813 | 2.38× | 50202/50202 | same |
| english | 26.365 | 61.585 | 2.34× | 49489/49489 | same |
| japanese | 25.359 | 44.228 | 1.74× | 18108/18108 | same |
| mandarin | 25.111 | 42.679 | 1.70× | 17639/17639 | same |
| features | 0.063 | 0.102 | 1.62× | 52/52 | same |

## Extended grapheme ranges

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 53.307 | 116.532 | 2.19× | 27383/27383 | same |
| hindi | 37.927 | 91.777 | 2.42× | 12642/12642 | same |
| korean | 45.195 | 74.635 | 1.65× | 21191/21191 | same |
| russian | 53.012 | 89.870 | 1.70× | 28544/28544 | same |
| source_code | 38.821 | 105.941 | 2.73× | 50202/50202 | same |
| english | 39.844 | 102.854 | 2.58× | 49472/49472 | same |
| japanese | 35.920 | 73.922 | 2.06× | 18045/18045 | same |
| mandarin | 34.343 | 70.036 | 2.04× | 17639/17639 | same |
| features | 0.082 | 0.231 | 2.82× | 41/42 | diff |

## Grapheme ranges with cluster width

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 105.738 | 246.282 | 2.33× | 27383/27383 | same |
| hindi | 67.698 | 249.539 | 3.69× | 12642/12642 | diff |
| korean | 81.942 | 197.100 | 2.41× | 21191/21191 | same |
| russian | 103.081 | 233.071 | 2.26× | 28544/28544 | same |
| source_code | 125.813 | 320.194 | 2.54× | 50202/50202 | same |
| english | 117.582 | 299.612 | 2.55× | 49472/49472 | same |
| japanese | 65.526 | 172.470 | 2.63× | 18045/18045 | same |
| mandarin | 63.806 | 170.181 | 2.67× | 17639/17639 | same |
| features | 0.153 | 0.517 | 3.38× | 41/42 | diff |

## Whole-text grapheme width

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 94.155 | 247.002 | 2.62× | 27275/27275 | same |
| hindi | 67.207 | 250.142 | 3.72× | 15702/16480 | diff |
| korean | 72.361 | 198.624 | 2.74× | 35376/35376 | same |
| russian | 91.898 | 237.667 | 2.59× | 28389/28389 | same |
| source_code | 2.778 | 313.555 | 112.87× | 48517/48517 | same |
| english | 4.001 | 297.246 | 74.29× | 49223/49223 | same |
| japanese | 60.527 | 173.178 | 2.86× | 33966/33966 | same |
| mandarin | 59.063 | 168.997 | 2.86× | 33576/33576 | same |
| features | 0.160 | 0.521 | 3.26× | 46/47 | diff |

## Unicode terminal property facts

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 55.801 | 116.184 | 2.08× | 27647/27647 | same |
| hindi | 51.134 | 95.619 | 1.87× | 19595/19595 | same |
| korean | 45.538 | 96.926 | 2.13× | 21191/21191 | same |
| russian | 55.777 | 115.462 | 2.07× | 28552/28552 | same |
| source_code | 84.278 | 127.816 | 1.52× | 50202/50202 | same |
| english | 81.014 | 130.498 | 1.61× | 49489/49489 | same |
| japanese | 42.878 | 84.875 | 1.98× | 18108/18108 | same |
| mandarin | 41.324 | 83.492 | 2.02× | 17639/17639 | same |
| features | 0.107 | 0.220 | 2.06× | 52/52 | same |

## Fused scalar terminal-property lookup

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 31.671 | 38.612 | 1.22× | 27647/27647 | same |
| hindi | 22.724 | 27.569 | 1.21× | 19595/19595 | same |
| korean | 24.573 | 30.432 | 1.24× | 21191/21191 | same |
| russian | 33.489 | 40.335 | 1.20× | 28552/28552 | same |
| source_code | 53.278 | 66.316 | 1.24× | 50202/50202 | same |
| english | 54.315 | 66.108 | 1.22× | 49489/49489 | same |
| japanese | 21.047 | 25.916 | 1.23× | 18108/18108 | same |
| mandarin | 19.930 | 25.525 | 1.28× | 17639/17639 | same |
| features | 0.064 | 0.085 | 1.33× | 52/52 | same |

## Full default case folding

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 85.194 | 84.130 | 0.99× | 27647/27647 | same |
| hindi | 71.321 | 69.434 | 0.97× | 19595/19595 | same |
| korean | 69.538 | 70.593 | 1.02× | 21191/21191 | same |
| russian | 86.673 | 87.692 | 1.01× | 28552/28552 | same |
| source_code | 106.511 | 109.655 | 1.03× | 50202/50202 | same |
| english | 107.735 | 109.625 | 1.02× | 49489/49489 | same |
| japanese | 49.618 | 67.013 | 1.35× | 18108/18108 | same |
| mandarin | 47.563 | 64.978 | 1.37× | 17639/17639 | same |
| features | 0.143 | 0.169 | 1.18× | 52/52 | same |

## Simple uppercase mapping

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 11.169 | 11.825 | 1.06× | 27647/27647 | same |
| hindi | 7.998 | 9.223 | 1.15× | 19595/19595 | same |
| korean | 8.889 | 11.293 | 1.27× | 21191/21191 | same |
| russian | 11.415 | 15.190 | 1.33× | 28552/28552 | same |
| source_code | 20.149 | 20.235 | 1.00× | 50202/50202 | same |
| english | 20.070 | 23.962 | 1.19× | 49489/49489 | same |
| japanese | 7.442 | 9.732 | 1.31× | 18108/18108 | same |
| mandarin | 7.372 | 9.375 | 1.27× | 17639/17639 | same |
| features | 0.021 | 0.027 | 1.29× | 52/52 | same |

## Simple lowercase mapping

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 11.073 | 11.753 | 1.06× | 27647/27647 | same |
| hindi | 8.032 | 8.719 | 1.09× | 19595/19595 | same |
| korean | 8.988 | 11.141 | 1.24× | 21191/21191 | same |
| russian | 12.047 | 15.552 | 1.29× | 28552/28552 | same |
| source_code | 20.422 | 20.801 | 1.02× | 50202/50202 | same |
| english | 20.677 | 24.268 | 1.17× | 49489/49489 | same |
| japanese | 7.567 | 9.314 | 1.23× | 18108/18108 | same |
| mandarin | 7.490 | 7.747 | 1.03× | 17639/17639 | same |
| features | 0.021 | 0.028 | 1.33× | 52/52 | same |

## Simple titlecase mapping

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 11.174 | 11.680 | 1.05× | 27647/27647 | same |
| hindi | 8.094 | 9.143 | 1.13× | 19595/19595 | same |
| korean | 8.907 | 11.231 | 1.26× | 21191/21191 | same |
| russian | 11.445 | 15.343 | 1.34× | 28552/28552 | same |
| source_code | 20.280 | 20.484 | 1.01× | 50202/50202 | same |
| english | 19.990 | 23.592 | 1.18× | 49489/49489 | same |
| japanese | 7.489 | 9.716 | 1.30× | 18108/18108 | same |
| mandarin | 7.381 | 9.395 | 1.27× | 17639/17639 | same |
| features | 0.022 | 0.029 | 1.32× | 52/52 | same |

## Exact numeric properties

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 12.712 | 28.476 | 2.24× | 27647/27647 | same |
| hindi | 9.674 | 21.555 | 2.23× | 19595/19595 | same |
| korean | 11.356 | 24.094 | 2.12× | 21191/21191 | same |
| russian | 15.347 | 33.911 | 2.21× | 28552/28552 | same |
| source_code | 23.467 | 54.055 | 2.30× | 50202/50202 | same |
| english | 25.566 | 54.901 | 2.15× | 49489/49489 | same |
| japanese | 9.391 | 20.400 | 2.17× | 18108/18108 | same |
| mandarin | 9.287 | 19.982 | 2.15× | 17639/17639 | same |
| features | 0.026 | 0.074 | 2.85× | 52/52 | same |

## Canonical combining class

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 10.636 | 11.382 | 1.07× | 27647/27647 | same |
| hindi | 6.986 | 7.901 | 1.13× | 19595/19595 | same |
| korean | 7.385 | 7.237 | 0.98× | 21191/21191 | same |
| russian | 10.121 | 10.442 | 1.03× | 28552/28552 | same |
| source_code | 18.067 | 17.100 | 0.95× | 50202/50202 | same |
| english | 18.061 | 17.123 | 0.95× | 49489/49489 | same |
| japanese | 6.577 | 7.085 | 1.08× | 18108/18108 | same |
| mandarin | 6.150 | 6.376 | 1.04× | 17639/17639 | same |
| features | 0.019 | 0.024 | 1.26× | 52/52 | same |

## Immediate decomposition facts

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 19.139 | 23.290 | 1.22× | 27647/27647 | same |
| hindi | 10.042 | 10.272 | 1.02× | 19595/19595 | same |
| korean | 11.284 | 13.139 | 1.16× | 21191/21191 | same |
| russian | 18.460 | 22.712 | 1.23× | 28552/28552 | same |
| source_code | 25.487 | 26.422 | 1.04× | 50202/50202 | same |
| english | 25.462 | 26.079 | 1.02× | 49489/49489 | same |
| japanese | 11.425 | 14.169 | 1.24× | 18108/18108 | same |
| mandarin | 10.590 | 19.442 | 1.84× | 17639/17639 | same |
| features | 0.035 | 0.042 | 1.20× | 52/52 | same |

## Incremental grapheme boundaries

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 68.374 | 178.260 | 2.61× | 27646/27646 | same |
| hindi | 54.259 | 180.516 | 3.33× | 19594/19594 | same |
| korean | 55.896 | 219.549 | 3.93× | 21190/21190 | same |
| russian | 66.579 | 174.904 | 2.63× | 28551/28551 | same |
| source_code | 121.589 | 236.460 | 1.94× | 50201/50201 | same |
| english | 95.275 | 219.335 | 2.30× | 49488/49488 | same |
| japanese | 45.210 | 113.575 | 2.51× | 18107/18107 | same |
| mandarin | 43.718 | 110.979 | 2.54× | 17638/17638 | same |
| features | 0.119 | 0.290 | 2.44× | 51/51 | diff |

## Ghostty scalar-width composition

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 46.247 | 74.832 | 1.62× | 27647/27647 | same |
| hindi | 38.073 | 61.978 | 1.63× | 19595/19595 | same |
| korean | 39.620 | 62.123 | 1.57× | 21191/21191 | same |
| russian | 46.768 | 74.563 | 1.59× | 28552/28552 | same |
| source_code | 66.671 | 99.069 | 1.49× | 50202/50202 | same |
| english | 55.562 | 81.085 | 1.46× | 49489/49489 | same |
| japanese | 33.352 | 59.718 | 1.79× | 18108/18108 | same |
| mandarin | 32.113 | 58.306 | 1.82× | 17639/17639 | same |
| features | 0.081 | 0.142 | 1.75× | 52/52 | same |

Ratio = uucode time / Zunic time; above 1 means Zunic took less time.
Exact output records are compared before and after timing; differences are reported rather than treated as benchmark failures.
Inputs are valid UTF-8 and file I/O is outside timing.
Measured traversal consumes each grapheme's start, end, and width; Zunic's renderable flag has no uucode counterpart and is excluded.
Both peers use Unicode 17.0.0; whole-grapheme width policies can still differ and are shown explicitly.
Terminal-property, case-mapping, numeric, normalization-fact, full-fold, and Ghostty-width rows agree exactly on these valid UTF-8 corpora.
The fused scalar lookup row receives predecoded code points, excluding UTF-8 decoding from its timing.
Simple case, numeric, combining-class, and decomposition rows also receive predecoded code points.
uucode exposes non-decimal numeric values as text; its numeric row includes parsing and reducing that text to Zunic's exact rational result.
Multi-result operations use independent field accumulators, combined once after traversal, to reduce checksum dependency-chain cost.
The focused streaming row intentionally records uucode's emoji-modifier tailoring against Zunic's default UAX #29 GB9 behavior.
