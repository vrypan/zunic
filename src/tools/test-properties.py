#!/usr/bin/env python3
"""Exhaustively verify the generated two-stage property table.

Run from the repository root:
    python3 src/tools/test-properties.py

This is deliberately an *independent* implementation. It re-derives every fact
from the pinned UCD files and decodes src/properties.zig by parsing the emitted
Zig, sharing no classification code with generate-properties.py. A mismatch
means the generator is wrong; it is never something to patch in the output.

It also closes plan 003's deferred exhaustive-verification follow-up.
"""

import re
import sys
from pathlib import Path

from check_unicode_version import check as check_unicode_version

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
SOURCE = ROOT / "properties.zig"
MAXCP = 0x110000

# EastAsianWidth-16.0.0.txt header: unlisted code points are "N", except
# unassigned ones in these blocks, which default to "W".
EAW_DEFAULT_W = (
    (0x3400, 0x4DBF), (0x4E00, 0x9FFF), (0xF900, 0xFAFF),
    (0x20000, 0x2FFFD), (0x30000, 0x3FFFD),
)


def read_property(filename, default, wanted=None):
    """Dense per-code-point array straight from a UCD property file."""
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


def parse_zig():
    """Decode the emitted table: enum orders, bit layout, index and data."""
    text = SOURCE.read_text(encoding="utf-8")

    def enum_order(name):
        body = re.search(rf"pub const {name} = enum\(u\d+\) \{{(.*?)\}};", text, re.S).group(1)
        return [item.strip() for item in body.replace("\n", " ").split(",") if item.strip()]

    struct = re.search(r"pub const Record = packed struct\(u32\) \{(.*?)\n\};", text, re.S).group(1)
    layout, offset = [], 0
    for field, kind in re.findall(r"\s*(\w+): (\w+)(?: = [^,]+)?,", struct):
        if kind == "bool":
            width = 1
        elif kind.startswith("u"):
            width = int(kind[1:])
        elif kind == "GraphemeClass":
            width = 4
        elif kind == "IndicConjunctBreak":
            width = 2
        elif kind == "LineBreak":
            width = 6
        else:
            sys.exit(f"unknown Record field type {kind}")
        layout.append((field, offset, width))
        offset += width
    if offset != 32:
        sys.exit(f"Record is {offset} bits, expected 32")

    shift = int(re.search(r"pub const record_block_shift = (\d+);", text).group(1))
    index = [int(v) for v in re.findall(r"(\d+),", re.search(
        r"pub const record_index = \[_\]u16\{(.*?)\n\};", text, re.S).group(1))]
    data = [int(v, 16) for v in re.findall(r"(0x[0-9A-Fa-f]+),", re.search(
        r"pub const record_data = \[_\]u32\{(.*?)\n\};", text, re.S).group(1))]
    return {
        "gcb": enum_order("GraphemeClass"),
        "incb": enum_order("IndicConjunctBreak"),
        "lb": enum_order("LineBreak"),
        "layout": dict((name, (off, width)) for name, off, width in layout),
        "shift": shift, "index": index, "data": data,
    }


def zig_name(value):
    return re.sub(r"[^a-z0-9]", "_", value.lower())


def main():
    check_unicode_version("UnicodeData-16.0.0.txt", "LineBreak-16.0.0.txt", "GraphemeBreakProperty-16.0.0.txt",
              "EastAsianWidth-16.0.0.txt", "emoji-data-16.0.0.txt", "DerivedCoreProperties-16.0.0.txt")

    gcb = read_property("GraphemeBreakProperty-16.0.0.txt", "Other")
    incb = read_property("DerivedCoreProperties-16.0.0.txt", "None",
                         {"InCB; Consonant", "InCB; Extend", "InCB; Linker"})
    ep = read_property("emoji-data-16.0.0.txt", "", {"Extended_Pictographic"})
    lb = read_property("LineBreak-16.0.0.txt", "XX")
    eaw = read_property("EastAsianWidth-16.0.0.txt", "N")
    category = read_categories()

    for lo, hi in EAW_DEFAULT_W:
        for cp in range(lo, hi + 1):
            if eaw[cp] == "N" and category[cp] == "Cn":
                eaw[cp] = "W"

    table = parse_zig()
    block_mask = (1 << table["shift"]) - 1

    def category_key(cp):
        raw = lb[cp]
        wide = eaw[cp] in ("W", "F", "H")
        return (raw, wide, raw == "QU" and category[cp] == "Pi",
                raw == "QU" and category[cp] == "Pf", raw == "OP" and not wide,
                raw == "CP" and not wide, ep[cp] == "Extended_Pictographic" and category[cp] == "Cn",
                raw == "SA" and category[cp] in ("Mn", "Mc"), cp == 0x2010, cp == 0x25CC)

    category_ids = {}
    expected_category = [0] * MAXCP
    scalar_order = list(range(0xD800)) + list(range(0xE000, MAXCP)) + list(range(0xD800, 0xE000))
    for cp in scalar_order:
        expected_category[cp] = category_ids.setdefault(category_key(cp), len(category_ids))

    def field(raw, name):
        offset, width = table["layout"][name]
        return (raw >> offset) & ((1 << width) - 1)

    failures = 0
    for cp in range(MAXCP):
        block = table["index"][cp >> table["shift"]]
        raw = table["data"][(block << table["shift"]) | (cp & block_mask)]

        wide = eaw[cp] in ("W", "F", "H")
        cat, lb_class = category[cp], lb[cp]
        pictographic = ep[cp] == "Extended_Pictographic"
        if 0xD800 <= cp <= 0xDFFF:
            width = 1
        elif cat in ("Mn", "Me", "Cf") and cp != 0x00AD:
            width = 0
        elif eaw[cp] in ("W", "F"):
            width = 2
        else:
            width = 1

        expected = {
            "gcb": table["gcb"].index(zig_name(gcb[cp])),
            "incb": table["incb"].index(zig_name(incb[cp].replace("InCB; ", ""))),
            "extended_pictographic": int(pictographic),
            "line_break": table["lb"].index(zig_name(lb_class)),
            "width": width,
            "lb_op30": int(lb_class == "OP" and not wide),
            "lb_cp30": int(lb_class == "CP" and not wide),
            "lb_qu_pi": int(lb_class == "QU" and cat == "Pi"),
            "lb_qu_pf": int(lb_class == "QU" and cat == "Pf"),
            "lb_ba_hyphen": int(lb_class == "BA" and cat == "Pd"),
            "lb_sa_mn_mc": int(lb_class == "SA" and cat in ("Mn", "Mc")),
            "east_asian_wide": int(wide),
            "ep_cn": int(pictographic and cat == "Cn"),
            "line_break_category": expected_category[cp],
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
          f"({len(table['data']) // (1 << table['shift'])} blocks, "
          f"{(len(table['index']) * 2 + len(table['data']) * 4) / 1024:.1f} KiB)")


if __name__ == "__main__":
    main()
