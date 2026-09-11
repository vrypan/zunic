#!/usr/bin/env python3
"""Exhaustively verify the generated General_Category / boolean-property table.

Run from the repository root:
    python3 src/tools/test-general-category.py

Deliberately independent: re-derives every fact from the pinned UCD files and
decodes src/tables/general_category.zig by parsing the emitted Zig, sharing no
classification code with generate-general-category.py. A mismatch means the
generator is wrong; it is never something to patch in the output.
"""

import re
import sys
from pathlib import Path

from check_unicode_version import check as check_unicode_version

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
SOURCE = ROOT / "tables/general_category.zig"
MAXCP = 0x110000

BOOLEANS = [
    ("Alphabetic", "is_alphabetic"),
    ("Lowercase", "is_lowercase"),
    ("Uppercase", "is_uppercase"),
    ("Cased", "is_cased"),
    ("Case_Ignorable", "is_case_ignorable"),
    ("Math", "is_math"),
    ("ID_Start", "is_id_start"),
    ("ID_Continue", "is_id_continue"),
    ("XID_Start", "is_xid_start"),
    ("XID_Continue", "is_xid_continue"),
    ("Default_Ignorable_Code_Point", "is_default_ignorable"),
    ("Grapheme_Base", "is_grapheme_base"),
    ("Grapheme_Extend", "is_grapheme_extend"),
]


def read_categories():
    values = ["Cn"] * MAXCP
    pending = None
    for raw in (DATA / "UnicodeData-17.0.0.txt").read_text(encoding="utf-8").splitlines():
        cp_text, name, category = raw.split(";")[:3]
        cp = int(cp_text, 16)
        if name.endswith(", First>"):
            pending = (cp, category)
        elif name.endswith(", Last>"):
            start, saved = pending
            for point in range(start, cp + 1):
                values[point] = saved
            pending = None
        else:
            values[cp] = category
    return values


def read_booleans():
    out = {name: bytearray(MAXCP) for name, _ in BOOLEANS}
    wanted = {name for name, _ in BOOLEANS}
    for raw in (DATA / "DerivedCoreProperties-17.0.0.txt").read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        left, prop = (part.strip() for part in line.split(";", 1))
        if prop not in wanted:
            continue
        if ".." in left:
            lo, hi = (int(part, 16) for part in left.split("..", 1))
        else:
            lo = hi = int(left, 16)
        for cp in range(lo, min(hi + 1, MAXCP)):
            out[prop][cp] = 1
    return out


def zig_name(value):
    # UnicodeData category abbreviations are always two letters; "No" is the
    # one that collides with a Zig keyword, so the generator suffixes it.
    return value.lower() + ("_" if value == "No" else "")


def parse_zig():
    text = SOURCE.read_text(encoding="utf-8")

    gc_order = [item.strip() for item in re.search(
        r"pub const GeneralCategory = enum\(u5\) \{(.*?)\};", text, re.S).group(1).split(",") if item.strip()]

    entries = re.findall(r"\.\{ (.*?) \},", re.search(
        r"pub const class_table = \[_\]GeneralCategoryProperties\{(.*?)\n\};", text, re.S).group(1))
    class_table = []
    for entry in entries:
        fields = {}
        for assignment in entry.split(", "):
            name, value = (part.strip() for part in assignment.split("="))
            name = name.lstrip(".")
            fields[name] = value
        class_table.append(fields)

    def array(name, dtype):
        body = re.search(rf"pub const {name} = \[_\]{dtype}\{{(.*?)\n\}};", text, re.S).group(1)
        return [int(v) for v in re.findall(r"(\d+),", body)]

    s1 = int(re.search(r"const gc_s1 = (\d+);", text).group(1))
    s2 = int(re.search(r"const gc_s2 = (\d+);", text).group(1))
    return {
        "gc_order": gc_order,
        "class_table": class_table,
        "stage1": array("gc_stage1", "u8"),
        "stage2": array("gc_stage2", "u16"),
        "stage3": array("gc_stage3", "u8"),
        "s1": s1,
        "s2": s2,
    }


def lookup(table, cp):
    """Mirrors `generalCategoryProperties`'s trie arithmetic exactly. Only
    called for cp in range(MAXCP) here, so the >= MAXCP guard the Zig
    function has is not exercised by this verifier."""
    s1, s2 = table["s1"], table["s2"]
    mid = table["stage1"][cp >> s1]
    leaf = table["stage2"][(mid << (s1 - s2)) | (cp >> s2 & ((1 << (s1 - s2)) - 1))]
    class_id = table["stage3"][(leaf << s2) | (cp & ((1 << s2) - 1))]
    return table["class_table"][class_id]


def main():
    check_unicode_version("UnicodeData-17.0.0.txt", "DerivedCoreProperties-17.0.0.txt")

    categories = read_categories()
    booleans = read_booleans()
    table = parse_zig()

    failures = 0
    for cp in range(MAXCP):
        entry = lookup(table, cp)
        want_category = "." + zig_name(categories[cp])
        got_category = entry["category"]
        if got_category != want_category:
            failures += 1
            if failures <= 20:
                print(f"U+{cp:04X} category: table={got_category} expected={want_category}")
        for source, accessor in BOOLEANS:
            want = "true" if booleans[source][cp] else "false"
            got = entry[accessor]
            if got != want:
                failures += 1
                if failures <= 20:
                    print(f"U+{cp:04X} {accessor}: table={got} expected={want}")

    if failures:
        sys.exit(f"{failures} mismatches over {MAXCP} code points")

    size = (len(table["stage1"]) + len(table["stage2"]) * 2 + len(table["stage3"])
            + len(table["class_table"]) * 4)
    print(f"ok: {MAXCP} code points verified against the pinned UCD "
          f"({len(table['class_table'])} classes, {size / 1024:.1f} KiB)")


if __name__ == "__main__":
    main()
