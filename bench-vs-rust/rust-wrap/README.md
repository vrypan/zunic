# Wrapping: Zunic and textwrap

[All Rust comparisons](../README.md)

Compare `text(bytes).wrap()` with textwrap 0.16.2 using the eight shared
texts in `../texts/`. The width is fixed by the harness.

## Run

From this directory:

```sh
make build
make test
make bench
make bench PAIRS=1
make report SUMMARY=../benchmarks/<run>/summary.json
make clean
```

See the [shared workflow](../README.md#build-test-and-benchmark) for build
settings, fetched inputs, sampling, and cleanup. Results are saved under
`../benchmarks/`; consult the report for the run you are examining.

## Timed operations

| Zunic | Rust | Work performed |
| --- | --- | --- |
| `zunic_iterate` | `textwrap_first_fit` | Consume every wrapped line |
| `zunic_collect` | `textwrap_first_fit` | Materialize and consume the full result |
| `zunic_first24` | `textwrap_first_fit_take24` | Consume the first 24 returned lines |

Zunic's iterator produces borrowed line spans. Its collection row allocates
an array of spans. Textwrap uses greedy `FirstFit` and returns an eager
`Vec<Cow<str>>`. In the first-24 comparison, Zunic stops its iterator after
24 lines; textwrap wraps the whole document before taking the first 24.
This difference in work matters when interpreting the ratio.

Rust validates raw bytes inside timing. Both peers checksum the returned line
bytes, including a line separator marker, and count lines. Collection rows
include allocation and destruction. File reads and dump checks are untimed.

## Inspect outputs

After `make build`:

```sh
./zig-out/bin/zunic-wrap-bench --help
./target/release/cellwidth-wrap-bench --help
./zig-out/bin/zunic-wrap-bench --dump
./target/release/cellwidth-wrap-bench ../texts --dump
```

The Rust executable retains its historical name but uses textwrap. Cellwidth
code is retained behind the optional `cellwidth-bench` feature and is excluded
from the default build, tests, and benchmark comparisons.

Dumps start each corpus with `case=<name> input=<hex>`. Every `L <hex>` record
is one returned line. Saved runs contain `zunic-before.dump` and
`rust-before.dump`, plus matching after-run dumps.

To inspect the first 24 English lines from a saved run, replace `<run>` below:

```sh
python3 - ../benchmarks/<run> <<'PYTHON'
from itertools import zip_longest
from pathlib import Path
import sys

run = Path(sys.argv[1])
outputs = {}
for peer in ("zunic", "rust"):
    lines, case = [], None
    for row in (run / f"{peer}-before.dump").read_text().splitlines():
        if row.startswith("case="):
            case = row.split()[0][5:]
        elif case == "english" and row.startswith("L "):
            lines.append(bytes.fromhex(row[2:]).decode("utf-8"))
    outputs[peer] = lines[:24]
for number, (z, r) in enumerate(zip_longest(outputs["zunic"], outputs["rust"]), 1):
    print(f"\nLine {number}: {'same' if z == r else 'DIFF'}")
    print(f"  Zunic: {z!r}\n  Rust:  {r!r}")
PYTHON
```

Quotes keep trailing spaces and empty lines visible. `None` means that peer
returned no line at that position. Full-document comparisons use every line;
the first-24 comparison uses only the prefix shown here.

## Versions and limits

Zunic uses Unicode 16.0.0. The pinned Rust dependencies use Unicode 15.0.0 for
line breaking and 17.0.0 for width. Width, word splitting, whitespace, and
final-line policies can also differ. Textwrap handles some ANSI sequences;
Zunic's Text view treats the input as plain text. Reports compare exact output
without trimming either peer's result.
