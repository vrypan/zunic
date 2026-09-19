# Latest benchmark timings

Recorded from
`benchmarks/20260919T183625Z-uucode-4d03b4/summary.json` on 2026-09-19.
The measured Zunic source tree was subsequently committed as `7bdbc2d`.
The benchmark used Zig 0.16.0, ReleaseFast, and the native CPU target on
macOS 26.6.2 ARM64.

Each table value is the median of three run medians. Runs used three
alternating peer pairs and 15 calibrated samples per executable and corpus.
The recorded executable sizes were 1,454,072 bytes for Zunic and 1,503,200
bytes for uucode.

## UTF-8 decoding

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 35.290 | 67.852 | 1.92× | 27647/27647 | same |
| hindi | 32.619 | 54.059 | 1.66× | 19595/19595 | same |
| korean | 31.957 | 50.159 | 1.57× | 21191/21191 | same |
| russian | 34.344 | 64.366 | 1.87× | 28552/28552 | same |
| source_code | 26.018 | 61.006 | 2.34× | 50202/50202 | same |
| english | 26.359 | 61.910 | 2.35× | 49489/49489 | same |
| japanese | 25.669 | 43.988 | 1.71× | 18108/18108 | same |
| mandarin | 24.094 | 42.518 | 1.76× | 17639/17639 | same |
| features | 0.090 | 0.142 | 1.58× | 75/75 | same |

## Extended grapheme ranges

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 59.297 | 114.680 | 1.93× | 27383/27383 | same |
| hindi | 46.432 | 93.087 | 2.00× | 12642/12642 | same |
| korean | 49.590 | 74.881 | 1.51× | 21191/21191 | same |
| russian | 59.876 | 88.541 | 1.48× | 28544/28544 | same |
| source_code | 51.541 | 105.028 | 2.04× | 50202/50202 | same |
| english | 52.392 | 104.314 | 1.99× | 49472/49472 | same |
| japanese | 43.776 | 74.222 | 1.70× | 18045/18045 | same |
| mandarin | 42.228 | 70.376 | 1.67× | 17639/17639 | same |
| features | 0.138 | 0.338 | 2.45× | 64/65 | diff |

## Grapheme ranges with cluster width

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 105.980 | 242.332 | 2.29× | 27383/27383 | same |
| hindi | 77.554 | 248.695 | 3.21× | 12642/12642 | diff |
| korean | 82.692 | 196.810 | 2.38× | 21191/21191 | same |
| russian | 105.653 | 233.329 | 2.21× | 28544/28544 | same |
| source_code | 126.585 | 317.954 | 2.51× | 50202/50202 | same |
| english | 118.460 | 304.866 | 2.57× | 49472/49472 | same |
| japanese | 67.671 | 172.770 | 2.55× | 18045/18045 | same |
| mandarin | 65.732 | 170.190 | 2.59× | 17639/17639 | same |
| features | 0.266 | 0.712 | 2.68× | 64/65 | diff |

## Whole-text grapheme width

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 98.813 | 242.626 | 2.46× | 27275/27275 | same |
| hindi | 64.473 | 247.373 | 3.84× | 15702/16480 | diff |
| korean | 75.444 | 195.573 | 2.59× | 35376/35376 | same |
| russian | 97.925 | 237.461 | 2.42× | 28389/28389 | same |
| source_code | 2.763 | 309.159 | 111.89× | 48517/48517 | same |
| english | 4.216 | 297.078 | 70.46× | 49223/49223 | same |
| japanese | 64.561 | 173.118 | 2.68× | 33966/33966 | same |
| mandarin | 62.511 | 169.034 | 2.70× | 33576/33576 | same |
| features | 0.277 | 0.713 | 2.57× | 64/66 | diff |

## Unicode terminal property facts

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 54.438 | 111.597 | 2.05× | 27647/27647 | same |
| hindi | 45.199 | 90.473 | 2.00× | 19595/19595 | same |
| korean | 44.600 | 91.180 | 2.04× | 21191/21191 | same |
| russian | 55.681 | 113.512 | 2.04× | 28552/28552 | same |
| source_code | 83.394 | 125.068 | 1.50× | 50202/50202 | same |
| english | 82.405 | 128.018 | 1.55× | 49489/49489 | same |
| japanese | 42.784 | 83.908 | 1.96× | 18108/18108 | same |
| mandarin | 41.104 | 83.372 | 2.03× | 17639/17639 | same |
| features | 0.149 | 0.315 | 2.11× | 75/75 | same |

## Fused scalar terminal-property lookup

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 32.264 | 38.545 | 1.19× | 27647/27647 | same |
| hindi | 23.035 | 27.403 | 1.19× | 19595/19595 | same |
| korean | 25.071 | 30.314 | 1.21× | 21191/21191 | same |
| russian | 33.683 | 40.287 | 1.20× | 28552/28552 | same |
| source_code | 53.581 | 66.999 | 1.25× | 50202/50202 | same |
| english | 54.577 | 66.080 | 1.21× | 49489/49489 | same |
| japanese | 21.502 | 26.078 | 1.21× | 18108/18108 | same |
| mandarin | 20.647 | 25.474 | 1.23× | 17639/17639 | same |
| features | 0.093 | 0.116 | 1.25× | 75/75 | same |

## Full default case folding

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 84.071 | 81.722 | 0.97× | 27647/27647 | same |
| hindi | 67.053 | 68.059 | 1.02× | 19595/19595 | same |
| korean | 66.746 | 69.551 | 1.04× | 21191/21191 | same |
| russian | 85.340 | 86.687 | 1.02× | 28552/28552 | same |
| source_code | 105.969 | 105.748 | 1.00× | 50202/50202 | same |
| english | 107.550 | 106.399 | 0.99× | 49489/49489 | same |
| japanese | 50.310 | 66.289 | 1.32× | 18108/18108 | same |
| mandarin | 47.728 | 64.533 | 1.35× | 17639/17639 | same |
| features | 0.202 | 0.238 | 1.18× | 75/75 | same |

## Simple uppercase mapping

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 12.861 | 11.863 | 0.92× | 27647/27647 | same |
| hindi | 9.259 | 8.970 | 0.97× | 19595/19595 | same |
| korean | 10.200 | 11.288 | 1.11× | 21191/21191 | same |
| russian | 13.274 | 15.090 | 1.14× | 28552/28552 | same |
| source_code | 23.410 | 21.338 | 0.91× | 50202/50202 | same |
| english | 23.112 | 23.676 | 1.02× | 49489/49489 | same |
| japanese | 8.660 | 9.696 | 1.12× | 18108/18108 | same |
| mandarin | 8.502 | 9.396 | 1.11× | 17639/17639 | same |
| features | 0.034 | 0.044 | 1.29× | 75/75 | same |

## Simple lowercase mapping

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 12.825 | 11.867 | 0.93× | 27647/27647 | same |
| hindi | 9.216 | 8.640 | 0.94× | 19595/19595 | same |
| korean | 10.376 | 11.127 | 1.07× | 21191/21191 | same |
| russian | 13.850 | 15.435 | 1.11× | 28552/28552 | same |
| source_code | 23.529 | 21.721 | 0.92× | 50202/50202 | same |
| english | 23.919 | 24.274 | 1.01× | 49489/49489 | same |
| japanese | 8.702 | 9.213 | 1.06× | 18108/18108 | same |
| mandarin | 8.515 | 7.819 | 0.92× | 17639/17639 | same |
| features | 0.035 | 0.043 | 1.23× | 75/75 | same |

## Simple titlecase mapping

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 12.829 | 11.767 | 0.92× | 27647/27647 | same |
| hindi | 9.265 | 8.996 | 0.97× | 19595/19595 | same |
| korean | 10.207 | 11.143 | 1.09× | 21191/21191 | same |
| russian | 13.279 | 15.299 | 1.15× | 28552/28552 | same |
| source_code | 23.537 | 20.641 | 0.88× | 50202/50202 | same |
| english | 23.224 | 23.855 | 1.03× | 49489/49489 | same |
| japanese | 8.641 | 9.576 | 1.11× | 18108/18108 | same |
| mandarin | 8.495 | 9.395 | 1.11× | 17639/17639 | same |
| features | 0.034 | 0.044 | 1.29× | 75/75 | same |

## Exact numeric properties

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 15.405 | 28.394 | 1.84× | 27647/27647 | same |
| hindi | 11.440 | 21.418 | 1.87× | 19595/19595 | same |
| korean | 13.168 | 24.013 | 1.82× | 21191/21191 | same |
| russian | 17.760 | 33.955 | 1.91× | 28552/28552 | same |
| source_code | 28.912 | 52.795 | 1.83× | 50202/50202 | same |
| english | 30.561 | 54.870 | 1.80× | 49489/49489 | same |
| japanese | 11.123 | 20.365 | 1.83× | 18108/18108 | same |
| mandarin | 10.805 | 20.009 | 1.85× | 17639/17639 | same |
| features | 0.044 | 0.098 | 2.23× | 75/75 | same |

## Primary Script property

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 11.532 | 9.888 | 0.86× | 27647/27647 | same |
| hindi | 8.165 | 7.009 | 0.86× | 19595/19595 | same |
| korean | 8.836 | 7.580 | 0.86× | 21191/21191 | same |
| russian | 11.918 | 10.218 | 0.86× | 28552/28552 | same |
| source_code | 21.128 | 17.296 | 0.82× | 50202/50202 | same |
| english | 21.186 | 17.552 | 0.83× | 49489/49489 | same |
| japanese | 7.555 | 6.528 | 0.86× | 18108/18108 | same |
| mandarin | 7.340 | 6.326 | 0.86× | 17639/17639 | same |
| features | 0.032 | 0.031 | 0.97× | 75/75 | same |

## Bidirectional scalar properties

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 15.820 | 20.071 | 1.27× | 27647/27647 | same |
| hindi | 11.215 | 13.755 | 1.23× | 19595/19595 | same |
| korean | 12.099 | 15.346 | 1.27× | 21191/21191 | same |
| russian | 16.344 | 21.146 | 1.29× | 28552/28552 | same |
| source_code | 28.711 | 36.589 | 1.27× | 50202/50202 | same |
| english | 28.636 | 35.223 | 1.23× | 49489/49489 | same |
| japanese | 10.358 | 14.526 | 1.40× | 18108/18108 | same |
| mandarin | 10.079 | 13.011 | 1.29× | 17639/17639 | same |
| features | 0.044 | 0.056 | 1.27× | 75/75 | same |

## Bidirectional scalar mappings

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 35.393 | 42.023 | 1.19× | 27647/27647 | same |
| hindi | 26.206 | 30.789 | 1.17× | 19595/19595 | same |
| korean | 29.697 | 34.502 | 1.16× | 21191/21191 | same |
| russian | 40.061 | 46.227 | 1.15× | 28552/28552 | same |
| source_code | 80.343 | 88.404 | 1.10× | 50202/50202 | same |
| english | 68.103 | 78.612 | 1.15× | 49489/49489 | same |
| japanese | 30.108 | 32.724 | 1.09× | 18108/18108 | same |
| mandarin | 24.729 | 29.063 | 1.18× | 17639/17639 | same |
| features | 0.097 | 0.124 | 1.28× | 75/75 | same |

## Canonical combining class

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 13.053 | 11.272 | 0.86× | 27647/27647 | same |
| hindi | 8.762 | 7.897 | 0.90× | 19595/19595 | same |
| korean | 9.378 | 7.212 | 0.77× | 21191/21191 | same |
| russian | 12.722 | 10.398 | 0.82× | 28552/28552 | same |
| source_code | 22.540 | 16.951 | 0.75× | 50202/50202 | same |
| english | 22.486 | 17.112 | 0.76× | 49489/49489 | same |
| japanese | 8.235 | 7.140 | 0.87× | 18108/18108 | same |
| mandarin | 7.845 | 6.341 | 0.81× | 17639/17639 | same |
| features | 0.034 | 0.033 | 0.97× | 75/75 | same |

## Immediate decomposition facts

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 17.854 | 23.634 | 1.32× | 27647/27647 | same |
| hindi | 9.967 | 11.213 | 1.13× | 19595/19595 | same |
| korean | 11.223 | 13.629 | 1.21× | 21191/21191 | same |
| russian | 17.956 | 23.251 | 1.29× | 28552/28552 | same |
| source_code | 25.462 | 28.425 | 1.12× | 50202/50202 | same |
| english | 25.412 | 28.376 | 1.12× | 49489/49489 | same |
| japanese | 11.394 | 14.319 | 1.26× | 18108/18108 | same |
| mandarin | 10.863 | 19.336 | 1.78× | 17639/17639 | same |
| features | 0.049 | 0.057 | 1.16× | 75/75 | same |

## Incremental grapheme boundaries

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 70.832 | 183.130 | 2.59× | 27646/27646 | same |
| hindi | 54.476 | 190.922 | 3.50× | 19594/19594 | same |
| korean | 53.207 | 211.059 | 3.97× | 21190/21190 | same |
| russian | 67.633 | 179.737 | 2.66× | 28551/28551 | same |
| source_code | 122.237 | 237.226 | 1.94× | 50201/50201 | same |
| english | 95.744 | 231.561 | 2.42× | 49488/49488 | same |
| japanese | 45.058 | 116.309 | 2.58× | 18107/18107 | same |
| mandarin | 43.656 | 112.551 | 2.58× | 17638/17638 | same |
| features | 0.173 | 0.434 | 2.51× | 74/74 | diff |

## Ghostty scalar-width composition

| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 47.548 | 80.254 | 1.69× | 27647/27647 | same |
| hindi | 48.186 | 59.782 | 1.24× | 19595/19595 | same |
| korean | 38.975 | 62.646 | 1.61× | 21191/21191 | same |
| russian | 48.037 | 79.061 | 1.65× | 28552/28552 | same |
| source_code | 67.294 | 98.218 | 1.46× | 50202/50202 | same |
| english | 54.996 | 80.609 | 1.47× | 49489/49489 | same |
| japanese | 35.688 | 59.737 | 1.67× | 18108/18108 | same |
| mandarin | 34.259 | 58.258 | 1.70× | 17639/17639 | same |
| features | 0.130 | 0.196 | 1.51× | 75/75 | same |

Ratio = uucode time / Zunic time; above 1 means Zunic took less time.
Exact output records are compared before and after timing; differences are reported rather than treated as benchmark failures.
Inputs are valid UTF-8 and file I/O is outside timing.
Measured traversal consumes each grapheme's start, end, and width; Zunic's renderable flag has no uucode counterpart and is excluded.
Both peers use Unicode 17.0.0; whole-grapheme width policies can still differ and are shown explicitly.
Terminal-property, case-mapping, numeric, Script, normalization-fact, full-fold, and Ghostty-width rows agree exactly on these valid UTF-8 corpora.
The fused scalar lookup row receives predecoded code points, excluding UTF-8 decoding from its timing.
Simple case, numeric, Script, bidi, combining-class, and decomposition rows also receive predecoded code points.
uucode exposes non-decimal numeric values as text; its numeric row includes parsing and reducing that text to Zunic's exact rational result.
Multi-result operations use independent field accumulators, combined once after traversal, to reduce checksum dependency-chain cost.
The focused streaming row intentionally records uucode's emoji-modifier tailoring against Zunic's default UAX #29 GB9 behavior.
