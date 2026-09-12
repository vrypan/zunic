#!/usr/bin/env python3
"""Independently verify terminal-facing Unicode and width properties."""

import re
import sys
from pathlib import Path

from check_unicode_version import check as check_unicode_version

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
SOURCE = ROOT / "tables/terminal_properties.zig"
MAXCP = 0x110000
SHIFT = 7
EAW = {"N": 0, "F": 1, "H": 2, "W": 3, "Na": 4, "A": 5}


def records(filename):
    for raw in (DATA / filename).read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        field, value = (part.strip() for part in line.split(";", 1))
        first, separator, last = field.partition("..")
        yield int(first, 16), int(last, 16) if separator else int(first, 16), value


def boolean(filename, property_name):
    result = bytearray(MAXCP)
    for lo, hi, value in records(filename):
        if value == property_name:
            result[lo : hi + 1] = b"\1" * (hi + 1 - lo)
    return result


def categories():
    # Only distinctions used by the width derivation need storage.
    codes = {"Cc": 1, "Cs": 2, "Zl": 3, "Zp": 4, "Mn": 5, "Me": 6}
    result = bytearray(MAXCP)
    pending = None
    for raw in (DATA / "UnicodeData-17.0.0.txt").read_text(encoding="utf-8").splitlines():
        fields = raw.split(";")
        cp, name, category = int(fields[0], 16), fields[1], fields[2]
        if name.endswith(", First>"):
            pending = cp, category
        elif name.endswith(", Last>"):
            lo, held = pending
            result[lo : cp + 1] = bytes([codes.get(held, 0)]) * (cp + 1 - lo)
            pending = None
        else:
            result[cp] = codes.get(category, 0)
    return result


def zig_array(text, name, kind, base):
    body = re.search(rf"const {name} = \[_\]{kind}\{{(.*?)\n\}};", text, re.S).group(1)
    pattern = r"0x[0-9a-f]+" if base == 16 else r"\d+"
    return [int(value, base) for value in re.findall(pattern, body)]


def main():
    files = ("UnicodeData-17.0.0.txt", "EastAsianWidth-17.0.0.txt",
             "GraphemeBreakProperty-17.0.0.txt", "DerivedCoreProperties-17.0.0.txt",
             "emoji-data-17.0.0.txt", "emoji-variation-sequences-17.0.0.txt")
    check_unicode_version(*files)

    eaw = bytearray(MAXCP)
    for lo, hi in ((0x3400, 0x4DBF), (0x4E00, 0x9FFF), (0xF900, 0xFAFF),
                   (0x20000, 0x2FFFD), (0x30000, 0x3FFFD)):
        eaw[lo : hi + 1] = bytes([EAW["W"]]) * (hi + 1 - lo)
    for lo, hi, value in records("EastAsianWidth-17.0.0.txt"):
        eaw[lo : hi + 1] = bytes([EAW[value]]) * (hi + 1 - lo)

    presentation = boolean("emoji-data-17.0.0.txt", "Emoji_Presentation")
    emoji = boolean("emoji-data-17.0.0.txt", "Emoji")
    emoji_component = boolean("emoji-data-17.0.0.txt", "Emoji_Component")
    modifier = boolean("emoji-data-17.0.0.txt", "Emoji_Modifier")
    modifier_base = boolean("emoji-data-17.0.0.txt", "Emoji_Modifier_Base")
    ignorables = boolean("DerivedCoreProperties-17.0.0.txt", "Default_Ignorable_Code_Point")
    variation_base = bytearray(MAXCP)
    for raw in (DATA / "emoji-variation-sequences-17.0.0.txt").read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if line:
            variation_base[int(line.split()[0], 16)] = 1

    gcb = bytearray(MAXCP)
    gcb_codes = {"Regional_Indicator": 1, "V": 2, "T": 3, "Prepend": 4}
    for lo, hi, value in records("GraphemeBreakProperty-17.0.0.txt"):
        if value in gcb_codes:
            gcb[lo : hi + 1] = bytes([gcb_codes[value]]) * (hi + 1 - lo)
    category = categories()

    text = SOURCE.read_text(encoding="utf-8")
    index = zig_array(text, "index", "u8", 10)
    table = zig_array(text, "data", "u16", 16)
    failures = 0
    for cp in range(MAXCP):
        cat = category[cp]
        if cat in (1, 2, 3, 4):
            standalone = 0
        elif cp == 0x00AD:
            standalone = 1
        elif ignorables[cp]:
            standalone = 0
        elif cp == 0x2E3A:
            standalone = 2
        elif cp == 0x2E3B:
            standalone = 3
        elif eaw[cp] in (EAW["W"], EAW["F"]) or gcb[cp] == 1:
            standalone = 2
        else:
            standalone = 1
        if cp == 0x20E3:
            standalone = 2
        zero = standalone == 0 or modifier[cp] or cat in (5, 6) or gcb[cp] in (2, 3, 4)
        expected = (eaw[cp] | presentation[cp] << 3 | variation_base[cp] << 4 |
                    modifier[cp] << 5 | modifier_base[cp] << 6 |
                    standalone << 7 | int(zero) << 9 | emoji[cp] << 10 |
                    emoji_component[cp] << 11)
        block = index[cp >> SHIFT]
        got = table[(block << SHIFT) | (cp & ((1 << SHIFT) - 1))]
        if got != expected:
            failures += 1
            if failures <= 20:
                print(f"U+{cp:04X}: table=0x{got:03X} expected=0x{expected:03X}")
    if failures:
        sys.exit(f"{failures} terminal-property mismatches over {MAXCP} code points")
    print(f"ok: {MAXCP} terminal property records verified ({len(set(index))} blocks)")


if __name__ == "__main__":
    main()
