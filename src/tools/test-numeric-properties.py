#!/usr/bin/env python3
"""Verify generated numeric properties against pinned UnicodeData."""

import filecmp
from fractions import Fraction
import re
import subprocess
import sys
import tempfile
from pathlib import Path

from check_unicode_version import check as check_unicode_version

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data/UnicodeData-17.0.0.txt"
SOURCE = ROOT / "tables/numeric_properties.zig"
GENERATOR = ROOT / "tools/generate-numeric-properties.py"
MAXCP = 0x110000


def array(text, name):
    body = re.search(rf"const {name} = \[_\]u8\{{(.*?)\n\}};", text, re.S).group(1)
    return [int(value) for value in re.findall(r"\d+", body)]


def main():
    check_unicode_version("UnicodeData-17.0.0.txt")
    with tempfile.TemporaryDirectory() as directory:
        generated = Path(directory) / "numeric_properties.zig"
        subprocess.run([sys.executable, str(GENERATOR), "--output", str(generated)],
                       check=True, stdout=subprocess.DEVNULL)
        if not filecmp.cmp(generated, SOURCE, shallow=False):
            raise SystemExit("generated numeric table is stale")

    expected = {}
    for raw in DATA.read_text(encoding="utf-8").splitlines():
        fields = raw.split(";")
        value = fields[6] or fields[7] or fields[8]
        if value:
            kind = "decimal" if fields[6] else "digit" if fields[7] else "numeric"
            expected[int(fields[0], 16)] = (kind, Fraction(value))

    text = SOURCE.read_text(encoding="utf-8")
    s1 = int(re.search(r"const s1 = (\d+);", text).group(1))
    s2 = int(re.search(r"const s2 = (\d+);", text).group(1))
    stage1, stage2, stage3 = (array(text, name) for name in ("stage1", "stage2", "stage3"))
    values = [(kind, Fraction(int(num), int(den))) for kind, num, den in re.findall(
        r"\.kind = \.(\w+), \.numerator = (-?\d+), \.denominator = (\d+)", text)]
    for cp in range(MAXCP):
        mid = stage1[cp >> s1]
        leaf = stage2[(mid << (s1 - s2)) | (cp >> s2 & ((1 << (s1 - s2)) - 1))]
        value_id = stage3[(leaf << s2) | (cp & ((1 << s2) - 1))]
        actual = None if value_id == 0 else values[value_id - 1]
        if actual != expected.get(cp):
            raise SystemExit(f"numeric mismatch at U+{cp:04X}: {actual} != {expected.get(cp)}")
    print(f"ok: {MAXCP} numeric property records verified")


if __name__ == "__main__":
    main()
