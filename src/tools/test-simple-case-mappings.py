#!/usr/bin/env python3
"""Verify generated simple case mappings against pinned UnicodeData."""

import filecmp
import re
import subprocess
import sys
import tempfile
from pathlib import Path

from check_unicode_version import check as check_unicode_version

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data/UnicodeData-17.0.0.txt"
SOURCE = ROOT / "tables/simple_case_mappings.zig"
GENERATOR = ROOT / "tools/generate-simple-case-mappings.py"
MAXCP = 0x110000


def array(text, name):
    body = re.search(rf"const {name} = \[_\]u8\{{(.*?)\n\}};", text, re.S).group(1)
    return [int(value) for value in re.findall(r"\d+", body)]


def main():
    check_unicode_version(DATA.name)
    with tempfile.TemporaryDirectory() as directory:
        generated = Path(directory) / SOURCE.name
        subprocess.run([sys.executable, str(GENERATOR), "--output", str(generated)],
                       check=True, stdout=subprocess.DEVNULL)
        if not filecmp.cmp(generated, SOURCE, shallow=False):
            raise SystemExit("generated simple case-mapping table is stale")

    expected = {}
    for raw in DATA.read_text(encoding="utf-8").splitlines():
        fields = raw.split(";")
        cp = int(fields[0], 16)
        expected[cp] = tuple(int(fields[index], 16) if fields[index] else cp
                             for index in (12, 13, 14))

    text = SOURCE.read_text(encoding="utf-8")
    s1 = int(re.search(r"const s1 = (\d+);", text).group(1))
    s2 = int(re.search(r"const s2 = (\d+);", text).group(1))
    stage1, stage2, stage3 = (array(text, name) for name in ("stage1", "stage2", "stage3"))
    mappings = [tuple(map(int, values)) for values in re.findall(
        r"\.uppercase = (-?\d+), \.lowercase = (-?\d+), \.titlecase = (-?\d+)", text)]
    for cp in range(MAXCP):
        mid = stage1[cp >> s1]
        leaf = stage2[(mid << (s1 - s2)) | (cp >> s2 & ((1 << (s1 - s2)) - 1))]
        mapping_id = stage3[(leaf << s2) | (cp & ((1 << s2) - 1))]
        actual = tuple(cp + delta for delta in mappings[mapping_id])
        want = expected.get(cp, (cp, cp, cp))
        if actual != want:
            raise SystemExit(f"simple case mismatch at U+{cp:04X}: {actual} != {want}")
    print(f"ok: {MAXCP} simple case-mapping records verified")


if __name__ == "__main__":
    main()
