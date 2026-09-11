# Rust comparison benchmarks

Compare the current Zunic working tree, including uncommitted changes, with
pinned Rust libraries. Run from a source checkout with Zig 0.16.0 or later,
Rust/Cargo, Python 3, curl, and Make installed.

> [!NOTE]
> Regardless of the shape of APIs, and language peculiarities, I needed
> a measure to compare my implementation to more mature ones and get a
> ballpark of "how fast can I do the same thing here and there".
>
> These tests are not always comparing apples-to-apples, and they may be
> methodologically weak in some cases. But they provide the baseline I needed.

| Suite | Rust library | Operations |
| --- | --- | --- |
| [Line breaking](rust-linebreak/README.md) | unicode-linebreak 0.1.5 | Line-break opportunities |
| [Normalization](rust-normalize/README.md) | unicode-normalization 0.1.24 | NFC, NFD, NFKC, and NFKD iteration |
| [Words](rust-words/README.md) | unicode-segmentation 1.13.3 | Word boundaries and word-like segments |
| [Wrapping](rust-wrap/README.md) | textwrap 0.16.2 | Full wrapping and first 24 lines |
| [ANSI stripping](rust-strip-ansi/README.md) | strip-ansi-escapes 0.2.1 | Reused and allocated output buffers |
| [Display width](rust-width/README.md) | unicode-width 0.2.2 | Whole-text display width |

<!-- recorded-results:start -->
## Recorded results: 870043a on MacBook Pro M4

**Date:** 2026-09-10. **Zunic commit:** `870043a`. **Machine:** MacBook Pro M4,
macOS 26.6.2 (arm64). **Compilers:** Zig 0.16.0 and Rust 1.97.1.
Zig ReleaseFast/native; Rust release/native with LTO and one code-generation unit.

These are the latest saved runs for each suite as of that date, with three
alternating pairs per suite and 15 samples per executable run. Each table uses
the median of the three run medians. No benchmarks were rerun for this snapshot.

`Rust/Zunic` above 1 means Zunic took less time; below 1 means Rust took less
time. The ranges below show the lowest and highest per-corpus ratios, not an
overall average. Expand a suite for its times, counts, and output comparisons.

| Suite | Operation | Rust/Zunic range | Exact outputs matched |
| --- | --- | ---: | ---: |
| Line breaking | Opportunities | 0.79–1.02× | 1/8 |
| Normalization | NFC | 1.13–1.49× | 8/8 |
| Normalization | NFD | 0.92–1.19× | 8/8 |
| Normalization | NFKC | 1.09–1.43× | 8/8 |
| Normalization | NFKD | 0.88–1.19× | 8/8 |
| Words | All boundaries, iterator | 1.22–6.63× | 8/8 |
| Words | All boundaries, collected | 0.94–2.92× | 8/8 |
| Words | Word-like segments | 1.22–3.59× | 8/8 |
| Wrapping | Full document, iterator | 1.62–2.93× | 0/8 |
| Wrapping | Full document, collected | 1.02–2.86× | 0/8 |
| Wrapping | First 24 lines | 22.72–92.14× | 2/8 |
| ANSI stripping | Reused output | 3.33–8.47× | 10/10 |
| ANSI stripping | Allocated output | 3.29–8.36× | 10/10 |

Wrapping outputs differ on every full-document corpus. The first-24 results
match only for `source_code` and `mandarin`. Zunic stops after 24 lines, while
textwrap wraps the whole input before selecting 24; those large timing ratios
include that difference in work. Whitespace and final empty lines are included
in output comparisons. Line breaking also differs across Unicode versions and
policies; the matching corpus in this run is listed in its table.

ANSI timings cover only the ten fixtures whose outputs match. The additional
control-byte and malformed-input diagnostics are excluded from these timings.

The `source_code` corpus's Rust/Zunic ratio on word boundaries jumped between
snapshots (1.71x to 6.63x on the lazy partition). Zunic gained an ASCII fast
path for word boundaries after the prior snapshot; `source_code` is mostly
ASCII, so this reflects a real Zunic speedup, not new Rust overhead or noise.

<details>
<summary>Line breaking — per-corpus results</summary>

Saved run: `benchmarks/20260910T202053Z-rust-machine-6e2384/summary.json`.

Unicode: Zunic **16.0.0**; unicode-linebreak 0.1.5 **15.0.0 with SA tailoring**.

### Line-break opportunities

| Corpus | Zunic µs | Rust µs | Rust/Zunic | Units Z/R | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 136.645 | 129.026 | 0.94× | 4698/4697 | diff |
| hindi | 107.938 | 103.453 | 0.96× | 3721/3717 | diff |
| korean | 126.586 | 111.479 | 0.88× | 14759/14759 | same |
| russian | 141.506 | 133.392 | 0.94× | 3889/3891 | diff |
| source_code | 285.879 | 226.070 | 0.79× | 7756/7756 | diff |
| english | 292.020 | 229.362 | 0.79× | 8029/8039 | diff |
| japanese | 114.566 | 107.152 | 0.94× | 14337/14332 | diff |
| mandarin | 103.144 | 105.191 | 1.02× | 14966/14893 | diff |

</details>

<details>
<summary>Normalization — per-corpus results</summary>

Saved run: `benchmarks/20260910T202440Z-normalize-bytes-a997a6/summary.json`.

Unicode: Zunic **16.0.0**; unicode-normalization 0.1.24 **16.0.0**.

### NFC

| Corpus | Zunic µs | Rust µs | Rust/Zunic | Units Z/R | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 264.879 | 313.167 | 1.18× | 27647/27647 | same |
| hindi | 165.905 | 239.205 | 1.44× | 19595/19595 | same |
| korean | 302.888 | 406.845 | 1.34× | 21191/21191 | same |
| russian | 252.483 | 316.123 | 1.25× | 28552/28552 | same |
| source_code | 280.643 | 414.586 | 1.48× | 50202/50202 | same |
| english | 276.822 | 411.166 | 1.49× | 49489/49489 | same |
| japanese | 197.343 | 223.241 | 1.13× | 18108/18108 | same |
| mandarin | 129.734 | 190.947 | 1.47× | 17639/17639 | same |

### NFD

| Corpus | Zunic µs | Rust µs | Rust/Zunic | Units Z/R | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 199.677 | 213.538 | 1.07× | 28526/28526 | same |
| hindi | 146.029 | 170.387 | 1.17× | 19595/19595 | same |
| korean | 292.867 | 280.280 | 0.96× | 41705/41705 | same |
| russian | 195.058 | 208.811 | 1.07× | 28947/28947 | same |
| source_code | 262.428 | 240.198 | 0.92× | 50202/50202 | same |
| english | 258.140 | 239.882 | 0.93× | 49489/49489 | same |
| japanese | 148.651 | 151.286 | 1.02× | 19129/19129 | same |
| mandarin | 109.066 | 129.419 | 1.19× | 17651/17651 | same |

### NFKC

| Corpus | Zunic µs | Rust µs | Rust/Zunic | Units Z/R | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 265.933 | 322.737 | 1.21× | 27647/27647 | same |
| hindi | 170.328 | 241.810 | 1.42× | 19595/19595 | same |
| korean | 306.870 | 401.517 | 1.31× | 21191/21191 | same |
| russian | 244.291 | 318.555 | 1.30× | 28553/28553 | same |
| source_code | 280.451 | 401.904 | 1.43× | 50202/50202 | same |
| english | 278.475 | 399.265 | 1.43× | 49489/49489 | same |
| japanese | 207.392 | 225.779 | 1.09× | 18118/18118 | same |
| mandarin | 149.380 | 205.858 | 1.38× | 17639/17639 | same |

### NFKD

| Corpus | Zunic µs | Rust µs | Rust/Zunic | Units Z/R | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 203.127 | 223.838 | 1.10× | 28526/28526 | same |
| hindi | 145.479 | 173.020 | 1.19× | 19595/19595 | same |
| korean | 293.374 | 280.862 | 0.96× | 41705/41705 | same |
| russian | 194.343 | 217.622 | 1.12× | 28948/28948 | same |
| source_code | 261.469 | 229.007 | 0.88× | 50202/50202 | same |
| english | 256.576 | 227.005 | 0.88× | 49489/49489 | same |
| japanese | 154.527 | 159.390 | 1.03× | 19139/19139 | same |
| mandarin | 126.713 | 144.913 | 1.14× | 17651/17651 | same |

</details>

<details>
<summary>Words — per-corpus results</summary>

Saved run: `benchmarks/20260910T202918Z-unicode-segmentation-zunic-words-fa66d8/summary.json`.

Unicode: Zunic **16.0.0**; unicode-segmentation 1.13.3 **17.0.0**.

### full partition, lazy, with offsets

| Corpus | Zunic µs | Rust µs | Rust/Zunic | Units Z/R | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 162.212 | 237.909 | 1.47× | 9802/9802 | same |
| hindi | 143.224 | 233.230 | 1.63× | 8083/8083 | same |
| korean | 147.390 | 189.461 | 1.29× | 10523/10523 | same |
| russian | 165.029 | 201.707 | 1.22× | 8794/8794 | same |
| source_code | 81.739 | 542.279 | 6.63× | 19320/19320 | same |
| english | 314.922 | 469.891 | 1.49× | 17432/17432 | same |
| japanese | 126.788 | 356.552 | 2.81× | 17184/17184 | same |
| mandarin | 120.237 | 242.683 | 2.02× | 17215/17215 | same |

### the same partition, materialized

| Corpus | Zunic µs | Rust µs | Rust/Zunic | Units Z/R | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 224.011 | 250.508 | 1.12× | 9802/9802 | same |
| hindi | 207.222 | 243.953 | 1.18× | 8083/8083 | same |
| korean | 207.997 | 202.620 | 0.97× | 10523/10523 | same |
| russian | 225.169 | 212.349 | 0.94× | 8794/8794 | same |
| source_code | 192.656 | 561.791 | 2.92× | 19320/19320 | same |
| english | 414.802 | 488.072 | 1.18× | 17432/17432 | same |
| japanese | 233.512 | 378.197 | 1.62× | 17184/17184 | same |
| mandarin | 223.180 | 264.177 | 1.18× | 17215/17215 | same |

### word-like segments only

| Corpus | Zunic µs | Rust µs | Rust/Zunic | Units Z/R | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 159.854 | 370.692 | 2.32× | 4639/4639 | same |
| hindi | 145.665 | 382.142 | 2.62× | 3628/3628 | same |
| korean | 146.549 | 343.987 | 2.35× | 4796/4796 | same |
| russian | 162.026 | 283.102 | 1.75× | 3787/3787 | same |
| source_code | 70.889 | 86.758 | 1.22× | 5520/5520 | same |
| english | 312.191 | 496.400 | 1.59× | 7883/7883 | same |
| japanese | 142.146 | 510.636 | 3.59× | 13914/13914 | same |
| mandarin | 132.497 | 351.443 | 2.65× | 14797/14797 | same |

</details>

<details>
<summary>Wrapping — per-corpus results</summary>

Saved run: `benchmarks/20260910T203247Z-textwrap-zunic-06ba5c/summary.json`.

Unicode: Zunic **16.0.0**; textwrap 0.16.2 **linebreak 15.0.0; width 17.0.0**.

### Full document: iterator vs textwrap

| Corpus | Zunic µs | Rust µs | Rust/Zunic | Units Z/R | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 298.993 | 585.182 | 1.96× | 427/427 | diff |
| hindi | 244.511 | 456.726 | 1.87× | 321/327 | diff |
| korean | 256.036 | 687.787 | 2.69× | 632/633 | diff |
| russian | 305.536 | 556.081 | 1.82× | 477/472 | diff |
| source_code | 50.685 | 82.058 | 1.62× | 1672/1673 | diff |
| english | 452.935 | 825.282 | 1.82× | 800/792 | diff |
| japanese | 231.363 | 662.937 | 2.87× | 629/630 | diff |
| mandarin | 224.613 | 658.023 | 2.93× | 699/700 | diff |

### Full document: collected results

| Corpus | Zunic µs | Rust µs | Rust/Zunic | Units Z/R | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 302.812 | 585.182 | 1.93× | 427/427 | diff |
| hindi | 247.530 | 456.726 | 1.85× | 321/327 | diff |
| korean | 260.645 | 687.787 | 2.64× | 632/633 | diff |
| russian | 309.430 | 556.081 | 1.80× | 477/472 | diff |
| source_code | 80.272 | 82.058 | 1.02× | 1672/1673 | diff |
| english | 460.410 | 825.282 | 1.79× | 800/792 | diff |
| japanese | 236.901 | 662.937 | 2.80× | 629/630 | diff |
| mandarin | 230.467 | 658.023 | 2.86× | 699/700 | diff |

### First 24 lines

| Corpus | Zunic µs | Rust µs | Rust/Zunic | Units Z/R | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 18.104 | 536.716 | 29.65× | 24/24 | diff |
| hindi | 18.004 | 409.036 | 22.72× | 24/24 | diff |
| korean | 8.424 | 639.001 | 75.85× | 24/24 | diff |
| russian | 14.569 | 504.751 | 34.65× | 24/24 | diff |
| source_code | 0.758 | 31.972 | 42.18× | 24/24 | same |
| english | 14.549 | 779.261 | 53.56× | 24/24 | diff |
| japanese | 6.696 | 616.968 | 92.14× | 24/24 | diff |
| mandarin | 8.506 | 609.552 | 71.66× | 24/24 | same |

</details>

<details>
<summary>ANSI stripping — per-corpus results</summary>

Saved run: `benchmarks/20260910T203540Z-strip-ansi-22a101/summary.json`.

Unicode: Zunic **not applicable (byte-only)**; strip-ansi-escapes 0.2.1 (vte 0.14.1) **not applicable (no Unicode property tables)**.

### Reused output: stripAnsi vs Writer

| Corpus | Zunic µs | Rust µs | Rust/Zunic | Units Z/R | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| plain_ascii | 4.640 | 39.302 | 8.47× | 4095/4095 | same |
| plain_ascii_64k | 73.164 | 613.674 | 8.39× | 65520/65520 | same |
| sparse_sgr | 4.529 | 36.922 | 8.15× | 3648/3648 | same |
| dense_sgr | 1.635 | 10.734 | 6.57× | 264/264 | same |
| unicode | 4.460 | 22.066 | 4.95× | 3484/3484 | same |
| osc_links | 2.371 | 12.437 | 5.25× | 495/495 | same |
| commands_only | 1.481 | 7.448 | 5.03× | 0/0 | same |
| custom_osc | 2.855 | 17.370 | 6.08× | 1116/1116 | same |
| split_grapheme | 2.757 | 17.265 | 6.26× | 1260/1260 | same |
| long_osc | 32.751 | 109.116 | 3.33× | 0/0 | same |

### Allocated output: stripAnsi + allocation vs strip

| Corpus | Zunic µs | Rust µs | Rust/Zunic | Units Z/R | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| plain_ascii | 4.586 | 38.327 | 8.36× | 4095/4095 | same |
| plain_ascii_64k | 78.116 | 614.133 | 7.86× | 65520/65520 | same |
| sparse_sgr | 4.543 | 37.369 | 8.23× | 3648/3648 | same |
| dense_sgr | 1.612 | 10.887 | 6.75× | 264/264 | same |
| unicode | 4.469 | 22.665 | 5.07× | 3484/3484 | same |
| osc_links | 2.370 | 12.374 | 5.22× | 495/495 | same |
| commands_only | 1.479 | 7.641 | 5.17× | 0/0 | same |
| custom_osc | 2.870 | 17.530 | 6.11× | 1116/1116 | same |
| split_grapheme | 2.762 | 17.634 | 6.38× | 1260/1260 | same |
| long_osc | 33.203 | 109.076 | 3.29× | 0/0 | same |

</details>

<!-- recorded-results:end -->

## Build, test, and benchmark

From the repository root:

```sh
make -C bench-vs-rust build
make -C bench-vs-rust test
make -C bench-vs-rust bench
make -C bench-vs-rust clean
```

The central Makefile runs the five suites sequentially. Each suite has the
same targets; for example:

```sh
make -C bench-vs-rust/rust-wrap bench PAIRS=1
```

- `build` fetches missing inputs and Cargo dependencies, then compiles both peers.
- `test` builds and runs the suite checks. The central target also checks the shared reporting tools and executable CLIs.
- `bench` builds current code and runs three alternating pairs. `PAIRS=1` is an exploratory run.
- `clean` removes build products and local caches. It keeps texts, Unicode fixtures, lockfiles, results, and shared toolchain caches.

Cargo dependencies are pinned in `Cargo.toml` and `Cargo.lock`. Their source
stays in Cargo's cache; the Rust files here are benchmark adapters. Zunic uses
local path dependencies. The suite is not included in the Zunic dependency
package.

Benchmarks use Zig ReleaseFast/native and Rust release/native with LTO and one
code-generation unit. The Python drivers select these settings explicitly;
Makefile build overrides do not change the benchmark configuration. Each
executable collects 15 samples with a 50 ms calibration target. Run on an
otherwise idle machine.

## Inputs

`make build` fetches eight reference texts from the
[unicode-segmentation corpus](https://github.com/unicode-rs/unicode-segmentation/tree/048d51fe1d9bac5ca7c56226d3a4b42f21d70be2/benches/texts)
into ignored `texts/`. [corpus.lock.json](corpus.lock.json) pins the GitHub
revision and file checksums. Existing files are checked and reused. The
upstream attribution and license files are fetched with the texts.

ANSI stripping uses its own checked-in synthetic [fixtures](rust-strip-ansi/texts/),
including malformed byte sequences. Zig embeds corpus bytes at build time;
Rust reads the same bytes before timing. Drivers check input identity.

## Manual execution

Each benchmark executable prints help with no arguments, `--help`, or `-h`.
Actions must be explicit:

| Argument | Action |
| --- | --- |
| `--bench` | Run timings |
| `--dump` | Print exact output records |
| `--check` | Print counts/checksums; available for wrap, words, and stripping |

Rust executables take `CORPUS_DIR` before the action. Zig uses embedded input.
Each suite page gives the executable names and commands. Line breaking also
accepts `--streams` as an alias for `--dump`. Normalization has a separately
labelled Rust `--bench-prevalidated` diagnostic.

## Read a report

Each run creates an ignored directory under `benchmarks/`, printed when the
run finishes. It contains `summary.json`, `comparison.md`, raw timing samples,
peer executables, and exact output evidence. The recorded results above are a
dated snapshot. Use a saved run's report when examining that run or comparing
changes; the snapshot does not update automatically.

Re-render any saved summary from the repository root:

```sh
make -C bench-vs-rust report SUMMARY=benchmarks/<run>/summary.json
python3 bench-vs-rust/benchmark_report.py bench-vs-rust/benchmarks/<run>/summary.json --format markdown
```

`Rust/Zunic` is Rust time divided by Zunic time. Ratios above 1.05 are green;
below 0.95 are red. `NO_COLOR=1` disables color and `FORCE_COLOR=1` enables it
for redirected output. `Units Z/R` shows the result counts for the two peers.
Equal counts do not imply equal outputs.

`Output` compares the actual result of that operation: full lines or first 24
lines, all word ranges or filtered ranges, each normalization form, stripped
bytes, or line-break opportunities. Trailing whitespace and empty lines count.
`same` means exact agreement; `diff` means a difference was found. Older
archives without enough evidence are labelled `unverified`.

Reports state each peer's Unicode version. Version and policy differences are
accepted constraints; they are not automatically Zunic bugs. The stripping
suite requires agreement on its timed fixtures and reports other cases
separately. Its byte APIs do not use Unicode property-table versions.

## What timing includes

Primary comparisons start from bytes. Required UTF-8 validation and decoding
happen inside timing; file I/O and output verification happen outside it.
Both peers consume results with the same operation-specific count/checksum.
Optimization barriers protect input and final results without blocking each
iteration. Allocation differences are described on the suite pages.

[benchmark_contract.py](benchmark_contract.py) parses protocol v1 and checks
timed results against dumps. [benchmark_report.py](benchmark_report.py) handles
the common `zunic-rust-benchmark/v1` summary and report format. Historical
archives under `private/benchmarks/` can also be passed to this reporter;
missing evidence is not replaced with a suite-wide agreement claim.
