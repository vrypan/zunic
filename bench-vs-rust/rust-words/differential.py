#!/usr/bin/env python3
"""Compare Zunic's word partition against unicode-segmentation, segment by segment.

This is the correctness half of the harness. It runs both peers with `--dump`
and reports every place they disagree, with the offending text quoted and the
code points named, so a difference can be judged rather than merely counted.

The two are pinned to different Unicode versions -- unicode-segmentation 1.13.3
carries Unicode 17.0.0, Zunic carries 16.0.0 -- so differences are expected and
a nonzero count is not automatically a bug. What matters is whether each one is
explained by a property that changed between the two releases. Use --verify to
have every difference checked against the two UCD releases and classified;
`--strict` then exits nonzero only if something is left unexplained.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
import unicodedata
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
CORPUS_DIR = HERE.parent / "texts"
CORPORA = ("arabic", "hindi", "korean", "russian", "source_code", "english", "japanese", "mandarin")
ZUNIC_BIN = HERE / "zig-out/bin/zunic-words-bench"
RUST_BIN = HERE / "target/release/unicode-words-bench"
# Word_Break, Alphabetic and General_Category for both pinned releases. 16.0.0
# comes from the repository's own vendored copies so no download is needed for
# the side we ship; 17.0.0 is fetched on demand and cached beside this script.
UCD = {
    "16.0.0": {
        "wb": HERE.parents[1] / "src/data/WordBreakProperty-16.0.0.txt",
        "dcp": HERE.parents[1] / "src/data/DerivedCoreProperties-16.0.0.txt",
        "ud": HERE.parents[1] / "src/data/UnicodeData-16.0.0.txt",
    },
    "17.0.0": {
        "wb": HERE / ".ucd/WordBreakProperty-17.0.0.txt",
        "dcp": HERE / ".ucd/DerivedCoreProperties-17.0.0.txt",
        "ud": HERE / ".ucd/UnicodeData-17.0.0.txt",
    },
}
URLS = {
    "wb": "https://www.unicode.org/Public/{v}/ucd/auxiliary/WordBreakProperty.txt",
    "dcp": "https://www.unicode.org/Public/{v}/ucd/DerivedCoreProperties.txt",
    "ud": "https://www.unicode.org/Public/{v}/ucd/UnicodeData.txt",
}


def dump(binary: Path, *args: str) -> dict[str, list[tuple[int, int, bool]]]:
    command = [str(binary), *args, "--dump"]
    result = subprocess.run(command, capture_output=True, text=True)
    result.check_returncode()
    cases: dict[str, list[tuple[int, int, bool]]] = {}
    current: list[tuple[int, int, bool]] | None = None
    for line in result.stdout.splitlines():
        if line.startswith("case="):
            current = []
            cases[line.split()[0].removeprefix("case=")] = current
        elif line.startswith("S "):
            _, start, end, flag = line.split()
            assert current is not None
            current.append((int(start), int(end), flag == "1"))
    return cases


def fetch(version: str, key: str) -> Path:
    path = UCD[version][key]
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        url = URLS[key].format(v=version)
        print(f"fetching {url}", file=sys.stderr)
        with urllib.request.urlopen(url) as response:
            path.write_bytes(response.read())
    return path


def read_ranges(path: Path, wanted: set[str] | None = None) -> dict[int, str]:
    values: dict[int, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        body = raw.split("#", 1)[0].strip()
        if not body:
            continue
        field, value = (part.strip() for part in body.split(";", 1))
        if wanted is not None and value not in wanted:
            continue
        first, _, last = field.partition("..")
        for cp in range(int(first, 16), int(last, 16) if last else int(first, 16)):
            values[cp] = value
        values[int(last, 16) if last else int(first, 16)] = value
    return values


def read_categories(path: Path) -> dict[int, str]:
    values: dict[int, str] = {}
    first_cp = None
    for raw in path.read_text(encoding="utf-8").splitlines():
        cp_text, name, category = raw.split(";")[:3]
        cp = int(cp_text, 16)
        if name.endswith(", First>"):
            first_cp = (cp, category)
        elif name.endswith(", Last>"):
            start, held = first_cp
            for point in range(start, cp + 1):
                values[point] = held
            first_cp = None
        else:
            values[cp] = category
    return values


def load_properties(version: str) -> dict[str, dict[int, str]]:
    return {
        "wb": read_ranges(fetch(version, "wb")),
        "alpha": read_ranges(fetch(version, "dcp"), {"Alphabetic"}),
        "gc": read_categories(fetch(version, "ud")),
    }


def facts(properties: dict[str, dict[int, str]], cp: int) -> tuple[str, bool]:
    word_like = properties["alpha"].get(cp) == "Alphabetic" or properties["gc"].get(cp, "Cn") in ("Nd", "Nl", "No")
    return properties["wb"].get(cp, "Other"), word_like


def name(cp: int) -> str:
    try:
        return unicodedata.name(chr(cp))
    except ValueError:
        return "<unnamed>"


def quote(text: str, start: int, end: int, pad: int = 12) -> str:
    body = text[max(0, start - pad):end + pad]
    return body.replace("\n", "\\n").replace("\r", "\\r")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--max-report", type=int, default=12, help="differences to describe per kind per corpus (verification is unlimited)")
    parser.add_argument("--verify", action="store_true", help="classify each difference against both UCD releases")
    parser.add_argument("--strict", action="store_true", help="exit nonzero if a difference is unexplained")
    args = parser.parse_args()
    if args.max_report < 0:
        parser.error("--max-report must be nonnegative")
    if args.strict and not args.verify:
        parser.error("--strict requires --verify")

    for binary in (ZUNIC_BIN, RUST_BIN):
        if not binary.exists():
            sys.exit(f"missing {binary}; run: zig build -Doptimize=ReleaseFast && cargo build --release")

    zunic = dump(ZUNIC_BIN)
    rust = dump(RUST_BIN, str(CORPUS_DIR))
    old, new = (load_properties("16.0.0"), load_properties("17.0.0")) if args.verify else ({}, {})

    print("Unicode versions: Zunic 16.0.0; unicode-segmentation 17.0.0. Version differences are expected.")

    total_segments = 0
    total_boundary = 0
    total_flag = 0
    unexplained = 0
    for case in CORPORA:
        raw = (CORPUS_DIR / f"{case}.txt").read_bytes()
        text = raw.decode("utf-8")
        # Peer offsets are UTF-8 byte offsets; Python str uses character indices.
        char_at_byte = {}
        byte_offset = 0
        for index, char in enumerate(text):
            char_at_byte[byte_offset] = index
            byte_offset += len(char.encode("utf-8"))
        char_at_byte[byte_offset] = len(text)
        z, r = zunic[case], rust[case]
        total_segments += len(z)

        # Boundaries first: the two partitions agree iff their boundary sets do.
        z_bounds = {start for start, _, _ in z}
        r_bounds = {start for start, _, _ in r}
        boundary_only_z = sorted(z_bounds - r_bounds)
        boundary_only_r = sorted(r_bounds - z_bounds)
        # Flags are only comparable on segments both engines actually produced.
        z_flags = {(start, end): flag for start, end, flag in z}
        r_flags = {(start, end): flag for start, end, flag in r}
        flag_diff = sorted(k for k in z_flags.keys() & r_flags.keys() if z_flags[k] != r_flags[k])

        total_boundary += len(boundary_only_z) + len(boundary_only_r)
        total_flag += len(flag_diff)
        status = "identical" if not (boundary_only_z or boundary_only_r or flag_diff) else "differs"
        print(
            f"case={case} bytes={len(raw)} segments_zunic={len(z)} segments_us={len(r)} "
            f"boundary_only_zunic={len(boundary_only_z)} boundary_only_us={len(boundary_only_r)} "
            f"flag_differences={len(flag_diff)} status={status}"
        )

        shown = 0
        for offset in boundary_only_z + boundary_only_r:
            side = "zunic only" if offset in z_bounds else "unicode-segmentation only"
            char_index = char_at_byte[offset]
            cp = ord(text[char_index]) if char_index < len(text) else 0
            note = ""
            if args.verify:
                a, b = facts(old, cp), facts(new, cp)
                note = f"  WB {a[0]}->{b[0]}, word_like {a[1]}->{b[1]}" if a != b else "  properties unchanged"
                if a == b:
                    unexplained += 1
            if shown >= args.max_report:
                continue
            print(f"    boundary at {offset} ({side}): U+{cp:04X} {name(cp)}{note}")
            print(f"        ...{quote(text, char_index, char_index + 1)}...")
            shown += 1
        remaining = len(boundary_only_z) + len(boundary_only_r) - shown
        if remaining:
            print(f"    ... {remaining} more boundary differences")

        shown = 0
        for start, end in flag_diff:
            segment = raw[start:end].decode("utf-8")
            note = ""
            if args.verify:
                changed = [cp for cp in map(ord, segment) if facts(old, cp) != facts(new, cp)]
                if changed:
                    cp = changed[0]
                    note = f"  U+{cp:04X} word_like {facts(old, cp)[1]}->{facts(new, cp)[1]}"
                else:
                    note = "  properties unchanged"
                    unexplained += 1
            if shown >= args.max_report:
                continue
            print(
                f"    flag at {start}..{end}: zunic={z_flags[(start, end)]} "
                f"us={r_flags[(start, end)]} {segment!r}{note}"
            )
            shown += 1
        remaining = len(flag_diff) - shown
        if remaining:
            print(f"    ... {remaining} more flag differences")

    print(
        f"\ntotal: {total_segments} zunic segments, {total_boundary} boundary differences, "
        f"{total_flag} flag differences"
    )
    if args.verify:
        print(f"unexplained by the 16.0.0 -> 17.0.0 property changes: {unexplained}")
        if args.strict and unexplained:
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
