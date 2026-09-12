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


def array(text, name, ty):
    body = re.search(rf"const {name} = \[_\]{ty}\{{(.*?)\n\}};", text, re.S).group(1)
    return [int(value) for value in re.findall(r"-?\d+", body)]


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
    shift = int(re.search(r"const shift = (\d+);", text).group(1))
    limit = int(re.search(r"const limit = (\d+);", text).group(1))
    stage1 = array(text, "stage1", "u16")
    deltas = [array(text, name, "i32") for name in ("uppercase", "lowercase", "titlecase")]
    leaf_size = 1 << shift
    assert len(stage1) * leaf_size == limit
    assert len(set(map(len, deltas))) == 1
    for offset in stage1:
        assert offset % leaf_size == 0 and offset + leaf_size <= len(deltas[0])
    for cp in range(0x200000):
        if cp >= limit:
            actual = (cp, cp, cp)
        else:
            index = stage1[cp >> shift] + (cp & (leaf_size - 1))
            actual = tuple(cp + values[index] for values in deltas)
        want = expected.get(cp, (cp, cp, cp))
        if actual != want:
            raise SystemExit(f"simple case mismatch at U+{cp:04X}: {actual} != {want}")
    print("ok: all 2097152 u21 simple case-mapping records verified")


if __name__ == "__main__":
    main()
