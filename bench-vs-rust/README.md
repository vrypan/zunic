# Rust comparison benchmarks

Compare the current Zunic working tree, including uncommitted changes, with
pinned Rust libraries. Run from a source checkout with Zig 0.16.0 or later,
Rust/Cargo, Python 3, curl, and Make installed.

| Suite | Rust library | Operations |
| --- | --- | --- |
| [Line breaking](rust-linebreak/README.md) | unicode-linebreak 0.1.5 | Line-break opportunities |
| [Normalization](rust-normalize/README.md) | unicode-normalization 0.1.24 | NFC and NFD iteration |
| [Words](rust-words/README.md) | unicode-segmentation 1.13.3 | Word boundaries and word-like segments |
| [Wrapping](rust-wrap/README.md) | textwrap 0.16.2 | Full wrapping and first 24 lines |
| [ANSI stripping](rust-strip-ansi/README.md) | strip-ansi-escapes 0.2.1 | Reused and allocated output buffers |

<!-- recorded-results:start -->
## Recorded results: 8075772 on MacBook Pro M4

**Date:** 2026-09-10. **Zunic commit:** `8075772`. **Machine:** MacBook Pro M4,
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
| Line breaking | Opportunities | 0.77–1.00× | 1/8 |
| Normalization | NFC | 1.02–1.49× | 8/8 |
| Normalization | NFD | 0.91–1.27× | 8/8 |
| Words | All boundaries, iterator | 1.27–2.83× | 8/8 |
| Words | All boundaries, collected | 0.95–1.66× | 8/8 |
| Words | Word-like segments | 0.27–3.64× | 8/8 |
| Wrapping | Full document, iterator | 1.62–2.97× | 0/8 |
| Wrapping | Full document, collected | 0.93–2.89× | 0/8 |
| Wrapping | First 24 lines | 23.28–92.62× | 2/8 |
| ANSI stripping | Reused output | 3.33–8.45× | 10/10 |
| ANSI stripping | Allocated output | 3.29–8.41× | 10/10 |

Wrapping outputs differ on every full-document corpus. The first-24 results
match only for `source_code` and `mandarin`. Zunic stops after 24 lines, while
textwrap wraps the whole input before selecting 24; those large timing ratios
include that difference in work. Whitespace and final empty lines are included
in output comparisons. Line breaking also differs across Unicode versions and
policies; the matching corpus in this run is listed in its table.

ANSI timings cover only the ten fixtures whose outputs match. The additional
control-byte and malformed-input diagnostics are excluded from these timings.

<details>
<summary>Line breaking — per-corpus results</summary>

Saved run: `benchmarks/20260910T155140Z-rust-machine-5a8ed5/summary.json`.

Unicode: Zunic **16.0.0**; unicode-linebreak 0.1.5 **15.0.0 with SA tailoring**.

### Line-break opportunities

| Corpus | Zunic µs | Rust µs | Rust/Zunic | Units Z/R | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 135.628 | 128.995 | 0.95× | 4698/4697 | diff |
| hindi | 111.649 | 104.159 | 0.93× | 3721/3717 | diff |
| korean | 126.592 | 110.999 | 0.88× | 14759/14759 | same |
| russian | 142.496 | 133.508 | 0.94× | 3889/3891 | diff |
| source_code | 282.476 | 225.097 | 0.80× | 7756/7756 | diff |
| english | 292.903 | 225.973 | 0.77× | 8029/8039 | diff |
| japanese | 116.388 | 106.861 | 0.92× | 14337/14332 | diff |
| mandarin | 104.778 | 105.066 | 1.00× | 14966/14893 | diff |

</details>

<details>
<summary>Normalization — per-corpus results</summary>

Saved run: `benchmarks/20260910T142029Z-normalize-bytes-29fc51/summary.json`.

Unicode: Zunic **16.0.0**; unicode-normalization 0.1.24 **16.0.0**.

### NFC

| Corpus | Zunic µs | Rust µs | Rust/Zunic | Units Z/R | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 287.319 | 312.654 | 1.09× | 27647/27647 | same |
| hindi | 174.020 | 238.602 | 1.37× | 19595/19595 | same |
| korean | 303.898 | 420.927 | 1.39× | 21191/21191 | same |
| russian | 273.792 | 312.584 | 1.14× | 28552/28552 | same |
| source_code | 324.373 | 415.005 | 1.28× | 50202/50202 | same |
| english | 320.963 | 400.335 | 1.25× | 49489/49489 | same |
| japanese | 217.237 | 222.599 | 1.02× | 18108/18108 | same |
| mandarin | 128.360 | 191.826 | 1.49× | 17639/17639 | same |

### NFD

| Corpus | Zunic µs | Rust µs | Rust/Zunic | Units Z/R | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 203.119 | 213.471 | 1.05× | 28526/28526 | same |
| hindi | 146.023 | 169.114 | 1.16× | 19595/19595 | same |
| korean | 288.213 | 280.788 | 0.97× | 41705/41705 | same |
| russian | 196.948 | 207.245 | 1.05× | 28947/28947 | same |
| source_code | 262.029 | 239.380 | 0.91× | 50202/50202 | same |
| english | 258.346 | 237.576 | 0.92× | 49489/49489 | same |
| japanese | 145.384 | 151.170 | 1.04× | 19129/19129 | same |
| mandarin | 101.544 | 129.073 | 1.27× | 17651/17651 | same |

</details>

<details>
<summary>Words — per-corpus results</summary>

Saved run: `benchmarks/20260910T142252Z-unicode-segmentation-zunic-words-b78001/summary.json`.

Unicode: Zunic **16.0.0**; unicode-segmentation 1.13.3 **17.0.0**.

### full partition, lazy, with offsets

| Corpus | Zunic µs | Rust µs | Rust/Zunic | Units Z/R | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 157.877 | 243.630 | 1.54× | 9802/9802 | same |
| hindi | 139.385 | 230.902 | 1.66× | 8083/8083 | same |
| korean | 141.515 | 194.944 | 1.38× | 10523/10523 | same |
| russian | 159.862 | 203.115 | 1.27× | 8794/8794 | same |
| source_code | 323.317 | 553.027 | 1.71× | 19320/19320 | same |
| english | 318.468 | 473.210 | 1.49× | 17432/17432 | same |
| japanese | 125.995 | 356.552 | 2.83× | 17184/17184 | same |
| mandarin | 118.070 | 243.301 | 2.06× | 17215/17215 | same |

### the same partition, materialized

| Corpus | Zunic µs | Rust µs | Rust/Zunic | Units Z/R | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 227.978 | 252.600 | 1.11× | 9802/9802 | same |
| hindi | 196.131 | 242.707 | 1.24× | 8083/8083 | same |
| korean | 205.878 | 204.182 | 0.99× | 10523/10523 | same |
| russian | 224.209 | 212.632 | 0.95× | 8794/8794 | same |
| source_code | 453.610 | 566.392 | 1.25× | 19320/19320 | same |
| english | 420.473 | 489.575 | 1.16× | 17432/17432 | same |
| japanese | 229.178 | 379.630 | 1.66× | 17184/17184 | same |
| mandarin | 223.491 | 264.130 | 1.18× | 17215/17215 | same |

### word-like segments only

| Corpus | Zunic µs | Rust µs | Rust/Zunic | Units Z/R | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 157.589 | 379.947 | 2.41× | 4639/4639 | same |
| hindi | 137.008 | 383.525 | 2.80× | 3628/3628 | same |
| korean | 139.278 | 351.295 | 2.52× | 4796/4796 | same |
| russian | 159.088 | 286.182 | 1.80× | 3787/3787 | same |
| source_code | 324.183 | 88.072 | 0.27× | 5520/5520 | same |
| english | 310.337 | 499.707 | 1.61× | 7883/7883 | same |
| japanese | 139.798 | 509.360 | 3.64× | 13914/13914 | same |
| mandarin | 130.767 | 350.188 | 2.68× | 14797/14797 | same |

</details>

<details>
<summary>Wrapping — per-corpus results</summary>

Saved run: `benchmarks/20260910T155547Z-textwrap-zunic-3e59a1/summary.json`.

Unicode: Zunic **16.0.0**; textwrap 0.16.2 **linebreak 15.0.0; width 17.0.0**.

### Full document: iterator vs textwrap

| Corpus | Zunic µs | Rust µs | Rust/Zunic | Units Z/R | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 297.795 | 587.067 | 1.97× | 427/427 | diff |
| hindi | 245.823 | 460.556 | 1.87× | 321/327 | diff |
| korean | 256.208 | 689.939 | 2.69× | 632/633 | diff |
| russian | 304.370 | 556.196 | 1.83× | 477/472 | diff |
| source_code | 50.713 | 82.139 | 1.62× | 1672/1673 | diff |
| english | 455.696 | 831.324 | 1.82× | 800/792 | diff |
| japanese | 231.443 | 673.317 | 2.91× | 629/630 | diff |
| mandarin | 225.400 | 669.799 | 2.97× | 699/700 | diff |

### Full document: collected results

| Corpus | Zunic µs | Rust µs | Rust/Zunic | Units Z/R | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 303.597 | 587.067 | 1.93× | 427/427 | diff |
| hindi | 249.496 | 460.556 | 1.85× | 321/327 | diff |
| korean | 268.784 | 689.939 | 2.57× | 632/633 | diff |
| russian | 313.427 | 556.196 | 1.77× | 477/472 | diff |
| source_code | 87.912 | 82.139 | 0.93× | 1672/1673 | diff |
| english | 460.008 | 831.324 | 1.81× | 800/792 | diff |
| japanese | 237.508 | 673.317 | 2.83× | 629/630 | diff |
| mandarin | 231.765 | 669.799 | 2.89× | 699/700 | diff |

### First 24 lines

| Corpus | Zunic µs | Rust µs | Rust/Zunic | Units Z/R | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| arabic | 18.066 | 539.877 | 29.88× | 24/24 | diff |
| hindi | 18.018 | 419.482 | 23.28× | 24/24 | diff |
| korean | 8.468 | 641.452 | 75.75× | 24/24 | diff |
| russian | 14.593 | 509.795 | 34.93× | 24/24 | diff |
| source_code | 0.759 | 32.418 | 42.71× | 24/24 | same |
| english | 14.452 | 787.064 | 54.46× | 24/24 | diff |
| japanese | 6.709 | 621.408 | 92.62× | 24/24 | diff |
| mandarin | 8.523 | 616.899 | 72.38× | 24/24 | same |

</details>

<details>
<summary>ANSI stripping — per-corpus results</summary>

Saved run: `benchmarks/20260910T142923Z-strip-ansi-565f7f/summary.json`.

Unicode: Zunic **not applicable (byte-only)**; strip-ansi-escapes 0.2.1 (vte 0.14.1) **not applicable (no Unicode property tables)**.

### Reused output: stripAnsi vs Writer

| Corpus | Zunic µs | Rust µs | Rust/Zunic | Units Z/R | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| plain_ascii | 4.535 | 37.103 | 8.18× | 4095/4095 | same |
| plain_ascii_64k | 72.512 | 612.719 | 8.45× | 65520/65520 | same |
| sparse_sgr | 4.556 | 36.580 | 8.03× | 3648/3648 | same |
| dense_sgr | 1.670 | 10.785 | 6.46× | 264/264 | same |
| unicode | 4.416 | 22.062 | 5.00× | 3484/3484 | same |
| osc_links | 2.351 | 12.094 | 5.14× | 495/495 | same |
| commands_only | 1.473 | 7.353 | 4.99× | 0/0 | same |
| custom_osc | 2.844 | 17.493 | 6.15× | 1116/1116 | same |
| split_grapheme | 2.748 | 17.458 | 6.35× | 1260/1260 | same |
| long_osc | 32.633 | 108.556 | 3.33× | 0/0 | same |

### Allocated output: stripAnsi + allocation vs strip

| Corpus | Zunic µs | Rust µs | Rust/Zunic | Units Z/R | Output |
| --- | ---: | ---: | ---: | ---: | :---: |
| plain_ascii | 4.528 | 38.064 | 8.41× | 4095/4095 | same |
| plain_ascii_64k | 76.589 | 607.293 | 7.93× | 65520/65520 | same |
| sparse_sgr | 4.533 | 37.197 | 8.21× | 3648/3648 | same |
| dense_sgr | 1.652 | 11.163 | 6.76× | 264/264 | same |
| unicode | 4.404 | 22.383 | 5.08× | 3484/3484 | same |
| osc_links | 2.357 | 12.136 | 5.15× | 495/495 | same |
| commands_only | 1.472 | 7.539 | 5.12× | 0/0 | same |
| custom_osc | 2.847 | 17.424 | 6.12× | 1116/1116 | same |
| split_grapheme | 2.742 | 17.470 | 6.37× | 1260/1260 | same |
| long_osc | 32.997 | 108.568 | 3.29× | 0/0 | same |

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
