#!/usr/bin/env python3
"""Independently verify the generated full default case-fold table."""

import re
import sys
from pathlib import Path

from check_unicode_version import check as check_unicode_version

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tables/case_folding.zig"
FIXTURE = ROOT / "data/CaseFolding-17.0.0.txt"
MAXCP = 0x110000


def array(text, name, kind, base=10):
    body = re.search(rf"pub const {name} = \[_\]{kind}\{{(.*?)\n\}};", text, re.S).group(1)
    pattern = r"0x[0-9a-f]+|\d+" if base == 0 else r"\d+"
    return [int(value, base) for value in re.findall(pattern, body)]


def main():
    check_unicode_version(FIXTURE.name)
    common, full = {}, {}
    for raw in FIXTURE.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        fields = [field.strip() for field in line.split(";")]
        mapping = tuple(int(value, 16) for value in fields[2].split())
        if fields[1] == "C":
            common[int(fields[0], 16)] = mapping
        elif fields[1] == "F":
            full[int(fields[0], 16)] = mapping
    expected = common | full

    text = SOURCE.read_text(encoding="utf-8")
    shift = int(re.search(r"pub const block_shift = (\d+);", text).group(1))
    index = array(text, "block_index", "u8")
    ids = array(text, "mapping_ids", "u16")
    mappings = []
    body = re.search(r"pub const mappings = \[_\]Mapping\{(.*?)\n\};", text, re.S).group(1)
    for values, length in re.findall(
        r"\.\{ \.codepoints = \.\{ ([^}]+) \}, \.len = (\d+) \},", body
    ):
        codepoints = tuple(int(value.strip(), 0) for value in values.split(","))
        mappings.append(codepoints[: int(length)])

    failures = 0
    mask = (1 << shift) - 1
    for cp in range(MAXCP):
        block = index[cp >> shift]
        mapping_id = ids[(block << shift) | (cp & mask)]
        got = mappings[mapping_id - 1] if mapping_id else (cp,)
        want = expected.get(cp, (cp,))
        if got != want:
            failures += 1
            if failures <= 20:
                print(f"U+{cp:04X}: table={got} expected={want}")
    if failures:
        sys.exit(f"{failures} case-fold mismatches over {MAXCP} code points")
    print(f"ok: {MAXCP} full default folds verified ({len(mappings)} mappings, "
          f"{len(set(index))} blocks)")


if __name__ == "__main__":
    main()
