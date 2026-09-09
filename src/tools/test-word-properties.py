#!/usr/bin/env python3
"""Exhaustively verify the generated word-segmentation property table.

Run from the repository root:
    python3 src/tools/test-word-properties.py

Independent by construction: it re-derives all three facts from the pinned UCD
files and decodes src/word_properties.zig by parsing the emitted Zig, sharing
no classification code with generate-word-properties.py. A mismatch means the
generator is wrong; it is never something to patch in the output.

It also re-runs the generator into a temporary location and compares the bytes,
so a nondeterministic generator fails here rather than silently producing a
different table on the next regeneration.
"""

import filecmp
import re
import subprocess
import sys
import tempfile
from pathlib import Path

from check_unicode_version import check as check_unicode_version

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
SOURCE = ROOT / "word_properties.zig"
GENERATOR = ROOT / "tools" / "generate-word-properties.py"
MAXCP = 0x110000
NUMBER_CATEGORIES = ("Nd", "Nl", "No")


def read_property(filename, default, wanted=None):
    values = [default] * MAXCP
    for raw in (DATA / filename).read_text(encoding="utf-8").splitlines():
        body = raw.split("#", 1)[0].strip()
        if not body:
            continue
        field, value = (part.strip() for part in body.split(";", 1))
        if wanted is not None and value not in wanted:
            continue
        first, _, last = field.partition("..")
        lo = int(first, 16)
        hi = int(last, 16) if last else lo
        for cp in range(lo, min(hi + 1, MAXCP)):
            values[cp] = value
    return values


def read_categories():
    values = ["Cn"] * MAXCP
    first_cp = None
    for raw in (DATA / "UnicodeData-16.0.0.txt").read_text(encoding="utf-8").splitlines():
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


def check_missing_default():
    """The Other default is read from the file, not assumed."""
    text = (DATA / "WordBreakProperty-16.0.0.txt").read_text(encoding="utf-8")
    match = re.search(r"#\s*@missing:\s*0000\.\.10FFFF;\s*(\w+)", text)
    if not match:
        sys.exit("WordBreakProperty-16.0.0.txt has no @missing line")
    if match.group(1) != "Other":
        sys.exit(f"unexpected @missing default {match.group(1)}")


def parse_zig():
    text = SOURCE.read_text(encoding="utf-8")

    body = re.search(r"pub const WordBreak = enum\(u5\) \{(.*?)\};", text, re.S).group(1)
    names = [item.strip() for item in body.replace("\n", " ").split(",") if item.strip()]

    struct = re.search(r"pub const WordProperties = packed struct\(u8\) \{(.*?)\n\};", text, re.S).group(1)
    layout, offset = {}, 0
    for field, kind in re.findall(r"\s*(\w+): (\w+)(?: = [^,]+)?,", struct):
        width = 1 if kind == "bool" else 5 if kind == "WordBreak" else int(kind[1:])
        layout[field] = (offset, width)
        offset += width
    if offset != 8:
        sys.exit(f"WordProperties is {offset} bits, expected 8")

    shift = int(re.search(r"pub const word_block_shift = (\d+);", text).group(1))
    index = [int(v) for v in re.findall(r"(\d+),", re.search(
        r"pub const word_index = \[_\]u16\{(.*?)\n\};", text, re.S).group(1))]
    data = [int(v, 16) for v in re.findall(r"(0x[0-9A-Fa-f]+),", re.search(
        r"pub const word_data = \[_\]u8\{(.*?)\n\};", text, re.S).group(1))]
    return names, layout, shift, index, data


def zig_name(value):
    return re.sub(r"[^a-z0-9]", "_", value.lower())


def check_regeneration():
    with tempfile.TemporaryDirectory() as tmp:
        copy = Path(tmp) / "word_properties.zig"
        copy.write_bytes(SOURCE.read_bytes())
        subprocess.run([sys.executable, str(GENERATOR)], check=True,
                       stdout=subprocess.DEVNULL)
        if not filecmp.cmp(copy, SOURCE, shallow=False):
            sys.exit("regeneration is not deterministic: src/word_properties.zig changed")


def main():
    check_unicode_version("WordBreakProperty-16.0.0.txt", "DerivedCoreProperties-16.0.0.txt",
              "UnicodeData-16.0.0.txt", "emoji-data-16.0.0.txt")

    check_missing_default()
    check_regeneration()

    wb = read_property("WordBreakProperty-16.0.0.txt", "Other")
    alphabetic = read_property("DerivedCoreProperties-16.0.0.txt", "", {"Alphabetic"})
    ep = read_property("emoji-data-16.0.0.txt", "", {"Extended_Pictographic"})
    category = read_categories()

    names, layout, shift, index, data = parse_zig()
    if len(names) != 19:
        sys.exit(f"expected 19 Word_Break values, found {len(names)}")
    block_mask = (1 << shift) - 1

    def field(raw, name):
        offset, width = layout[name]
        return (raw >> offset) & ((1 << width) - 1)

    failures = 0
    for cp in range(MAXCP):
        block = index[cp >> shift]
        raw = data[(block << shift) | (cp & block_mask)]
        expected = {
            "wb": names.index(zig_name(wb[cp])),
            "word_like": int(alphabetic[cp] == "Alphabetic" or category[cp] in NUMBER_CATEGORIES),
            "extended_pictographic": int(ep[cp] == "Extended_Pictographic"),
            "_padding": 0,
        }
        for name, want in expected.items():
            got = field(raw, name)
            if got != want:
                failures += 1
                if failures <= 20:
                    print(f"U+{cp:04X} {name}: table={got} expected={want}")
    if failures:
        sys.exit(f"{failures} mismatches over {MAXCP} code points")
    print(f"ok: {MAXCP} code points verified against the pinned UCD "
          f"({len(data) // (1 << shift)} blocks, "
          f"{(len(index) * 2 + len(data)) / 1024:.1f} KiB)")


if __name__ == "__main__":
    main()
