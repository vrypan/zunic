#!/usr/bin/env python3
"""Exhaustively verify the generated stream-safe counts.

Run from the repository root:
    python3 src/tools/test-stream-safe-properties.py

Independent by construction: it re-derives the NFKD form of every code point
from the pinned UCD and decodes src/stream_safe_properties.zig by parsing the
emitted Zig, sharing no code with the generator. It also re-runs the generator
into a temporary location and compares bytes.
"""

import re
import subprocess
import sys
import tempfile
from pathlib import Path

from check_unicode_version import check as check_unicode_version

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
SOURCE = ROOT / "stream_safe_properties.zig"
GENERATOR = ROOT / "tools" / "generate-stream-safe-properties.py"
MAXCP = 0x110000

S_BASE, L_BASE, V_BASE, T_BASE = 0xAC00, 0x1100, 0x1161, 0x11A7
L_COUNT, V_COUNT, T_COUNT = 19, 21, 28
N_COUNT = V_COUNT * T_COUNT
S_COUNT = L_COUNT * N_COUNT


def read_unicode_data():
    ccc, mapping = {}, {}
    for raw in (DATA / "UnicodeData-16.0.0.txt").read_text(encoding="utf-8").splitlines():
        parts = raw.split(";")
        cp = int(parts[0], 16)
        if int(parts[3]):
            ccc[cp] = int(parts[3])
        text = parts[5].strip()
        if text:
            items = text.split()
            # Keep compatibility mappings; only the <tag> is dropped.
            if items[0].startswith("<"):
                items = items[1:]
            mapping[cp] = [int(item, 16) for item in items]
    return ccc, mapping


def parse_zig():
    text = SOURCE.read_text(encoding="utf-8")

    def array(name):
        body = re.search(rf"pub const {name} = \[_\]u8\{{(.*?)\n?\}};", text, re.S).group(1)
        return [int(v, 16) if v.startswith("0x") else int(v) for v in re.findall(r"(0x[0-9A-Fa-f]+|\d+),", body)]

    return {
        "class_table": array("class_table"),
        "stage1": array("class_stage1"),
        "stage2": array("class_stage2"),
        "stage3": array("class_stage3"),
        "limit": int(re.search(r"pub const class_limit: u21 = (0x[0-9A-Fa-f]+);", text).group(1), 16),
        "above": int(re.search(r"pub const class_above_limit: u8 = (\d+);", text).group(1)),
        "s1": int(re.search(r"const class_s1 = (\d+);", text).group(1)),
        "s2": int(re.search(r"const class_s2 = (\d+);", text).group(1)),
        "stream_safe_limit": int(re.search(r"pub const stream_safe_limit: usize = (\d+);", text).group(1)),
        "cgj": int(re.search(r"pub const combining_grapheme_joiner: u21 = (0x[0-9A-Fa-f]+);", text).group(1), 16),
    }


def check_regeneration():
    with tempfile.TemporaryDirectory() as tmp:
        copy = Path(tmp) / "stream_safe_properties.zig"
        subprocess.run([sys.executable, str(GENERATOR), "--output", str(copy)],
                       check=True, stdout=subprocess.DEVNULL)
        if copy.read_bytes() != SOURCE.read_bytes():
            sys.exit("generated stream-safe tables are stale or regeneration is not deterministic")


def main():
    check_unicode_version("UnicodeData-16.0.0.txt")
    check_regeneration()
    ccc, mapping = read_unicode_data()
    table = parse_zig()

    if table["stream_safe_limit"] != 30:
        sys.exit(f"stream_safe_limit is {table['stream_safe_limit']}; UAX #15 section 13 says 30")
    if table["cgj"] != 0x034F:
        sys.exit(f"combining_grapheme_joiner is U+{table['cgj']:04X}; expected U+034F")

    cache = {}

    def nfkd(cp):
        if cp in cache:
            return cache[cp]
        if S_BASE <= cp < S_BASE + S_COUNT:
            index = cp - S_BASE
            out = [L_BASE + index // N_COUNT, V_BASE + (index % N_COUNT) // T_COUNT]
            if index % T_COUNT:
                out.append(T_BASE + index % T_COUNT)
        elif cp in mapping:
            out = []
            for part in mapping[cp]:
                out.extend(nfkd(part))
        else:
            out = [cp]
        cache[cp] = out
        return out

    s1, s2 = table["s1"], table["s2"]
    mid_bits = s1 - s2

    def counts_of(cp):
        if cp < 128:
            return 0, 0, True
        if cp >= table["limit"]:
            packed = table["class_table"][table["above"]]
        else:
            mid = table["stage1"][cp >> s1]
            leaf = table["stage2"][(mid << mid_bits) | (cp >> s2 & ((1 << mid_bits) - 1))]
            packed = table["class_table"][table["stage3"][(leaf << s2) | (cp & ((1 << s2) - 1))]]
        return packed & 7, packed >> 3 & 7, bool(packed >> 6 & 1)

    failures = 0
    worst_run = 0
    for cp in range(MAXCP):
        parts = nfkd(cp)
        leading = 0
        for part in parts:
            if ccc.get(part, 0):
                leading += 1
            else:
                break
        trailing = 0
        for part in reversed(parts):
            if ccc.get(part, 0):
                trailing += 1
            else:
                break
        want = (leading, trailing, any(ccc.get(part, 0) == 0 for part in parts))
        got = counts_of(cp)
        if got != want:
            failures += 1
            if failures <= 20:
                print(f"U+{cp:04X}: table={got} expected={want}")
        run = 0
        for part in parts:
            run = run + 1 if ccc.get(part, 0) else 0
            worst_run = max(worst_run, run)

    # Insertion only ever happens before a scalar, so a scalar whose own NFKD
    # holds more than the limit could not be made stream safe at all.
    if worst_run > table["stream_safe_limit"]:
        failures += 1
        print(f"a single scalar's NFKD has {worst_run} consecutive non-starters, over the limit")

    if failures:
        sys.exit(f"{failures} mismatches over {MAXCP} code points")
    size = len(table["class_table"]) + len(table["stage1"]) + len(table["stage2"]) + len(table["stage3"])
    print(f"ok: {MAXCP} code points verified against the pinned UCD")
    print(f"    {len(table['class_table'])} classes, {size} bytes")
    print(f"    worst NFKD non-starter run in one scalar: {worst_run} (limit {table['stream_safe_limit']})")


if __name__ == "__main__":
    main()
