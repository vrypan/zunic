#!/usr/bin/env python3
"""Independently verify generated and compiled bidi properties against UCD."""

import argparse
import filecmp
import re
import subprocess
import sys
import tempfile
from pathlib import Path

from check_unicode_version import check as check_unicode_version

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
SOURCE = ROOT / "tables/bidi_properties.zig"
GENERATOR = ROOT / "tools/generate-bidi-properties.py"
MAX_CP = 0x110000
U21_LIMIT = 0x200000
BIDI_ORDER = (
    "L", "LRE", "LRO", "R", "AL", "RLE", "RLO", "PDF", "EN", "ES", "ET",
    "AN", "CS", "NSM", "BN", "B", "S", "WS", "ON", "LRI", "RLI", "FSI",
    "PDI",
)


def rows(path):
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if line:
            yield [field.strip() for field in line.split(";")]


def interval(text):
    parts = text.split("..", 1)
    return int(parts[0], 16), int(parts[-1], 16)


def expected():
    aliases, canonical = {}, []
    for fields in rows(DATA / "PropertyValueAliases-17.0.0.txt"):
        if fields[0] == "bc":
            canonical.append((fields[1], fields[2]))
            for alias in fields[1:]:
                if alias:
                    aliases[alias] = fields[1]
    by_short = dict(canonical)
    ordered = [(short, by_short[short]) for short in BIDI_ORDER]
    ids = {short: value for value, (short, _) in enumerate(ordered)}
    classes = bytearray([ids["L"]]) * MAX_CP
    source = (DATA / "DerivedBidiClass-17.0.0.txt").read_text(encoding="utf-8")
    missing = re.findall(r"^# @missing:\s*([^;]+);\s*(\S+)", source, re.M)
    if len(missing) != 24:
        raise SystemExit("unexpected Bidi_Class defaults")
    for area, name in missing:
        lo, hi = interval(area.strip())
        classes[lo:hi + 1] = bytes([ids[aliases[name]]]) * (hi - lo + 1)
    for area, name, *_ in rows(DATA / "DerivedBidiClass-17.0.0.txt"):
        lo, hi = interval(area)
        classes[lo:hi + 1] = bytes([ids[aliases[name]]]) * (hi - lo + 1)

    mirrored = bytearray(MAX_CP)
    start = None
    for fields in rows(DATA / "UnicodeData-17.0.0.txt"):
        cp = int(fields[0], 16)
        if fields[1].endswith(", First>"):
            start = cp
            continue
        lo = start if fields[1].endswith(", Last>") else cp
        start = None
        if any(value != ids[fields[4]] for value in classes[lo:cp + 1]):
            raise SystemExit(f"UnicodeData Bidi_Class disagreement at U+{cp:04X}")
        mirrored[lo:cp + 1] = bytes([fields[9] == "Y"]) * (cp - lo + 1)

    mirrors = {int(a, 16): int(b, 16) for a, b, *_ in rows(DATA / "BidiMirroring-17.0.0.txt")}
    brackets = {int(a, 16): (int(b, 16), kind) for a, b, kind, *_ in rows(DATA / "BidiBrackets-17.0.0.txt")}
    combined = bytearray(value | (flag << 5) for value, flag in zip(classes, mirrored))
    for cp, (_, kind) in brackets.items():
        combined[cp] |= (1 if kind == "o" else 2) << 6
    return ordered, combined, mirrors, {cp: target for cp, (target, _) in brackets.items()}


def array(text, name):
    match = re.search(rf"const {name} = \[_\]u(?:8|16)\{{(.*?)\n\}};", text, re.S)
    if not match:
        raise SystemExit(f"cannot parse generated {name}")
    return [int(value, 0) for value in re.findall(r"0x[0-9A-Fa-f]+|\d+", match.group(1))]


def generated_values(text):
    stage1, stage2 = array(text, "property_stage1"), array(text, "property_stage2")
    mirror_stage1, mirror_stage2 = array(text, "mirror_stage1"), array(text, "mirror_stage2")
    bracket_stage1, bracket_stage2 = array(text, "bracket_stage1"), array(text, "bracket_stage2")
    if (len(stage1), len(stage2), len(mirror_stage1), len(mirror_stage2), len(bracket_stage1), len(bracket_stage2)) != (8704, 24448, 1024, 1856, 1024, 1152):
        raise SystemExit("generated bidi table geometry changed")
    actual_mirrors = {}
    for cp in range(0x10000):
        value = mirror_stage2[(mirror_stage1[cp >> 6] << 6) | (cp & 63)]
        if value != 0xFFFF:
            actual_mirrors[cp] = value
    actual_brackets = {}
    for cp in range(0x10000):
        value = bracket_stage2[(bracket_stage1[cp >> 6] << 6) | (cp & 63)]
        if value != 0xFFFF:
            actual_brackets[cp] = value
    return stage1, stage2, actual_mirrors, actual_brackets


def record(prop, mirror, bracket):
    return bytes((prop, mirror is not None, (mirror or 0) & 255, ((mirror or 0) >> 8) & 255,
                  ((mirror or 0) >> 16) & 255, bracket is not None, (bracket or 0) & 255,
                  ((bracket or 0) >> 8) & 255, ((bracket or 0) >> 16) & 255))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--compiled", action="store_true")
    args = parser.parse_args()
    check_unicode_version("DerivedBidiClass-17.0.0.txt", "BidiMirroring-17.0.0.txt", "BidiBrackets-17.0.0.txt")
    subprocess.run([sys.executable, str(GENERATOR), "--check-inputs"], check=True, stdout=subprocess.DEVNULL)
    with tempfile.TemporaryDirectory() as directory:
        output = Path(directory) / "bidi_properties.zig"
        subprocess.run([sys.executable, str(GENERATOR), "--output", str(output)], check=True, stdout=subprocess.DEVNULL)
        if not filecmp.cmp(output, SOURCE, shallow=False):
            raise SystemExit("generated bidi table is stale")

    _, wanted, mirrors, brackets = expected()
    stage1, stage2, actual_mirrors, actual_brackets = generated_values(SOURCE.read_text(encoding="utf-8"))
    if actual_mirrors != mirrors or actual_brackets != brackets:
        raise SystemExit("generated bidi mapping tables differ from UCD")
    for cp in range(MAX_CP):
        value = stage2[(stage1[cp >> 7] << 7) | (cp & 127)]
        if value != wanted[cp]:
            raise SystemExit(f"generated bidi property mismatch at U+{cp:04X}")

    if args.compiled:
        with tempfile.TemporaryFile() as output:
            process = subprocess.run(["zig", "build", "--global-cache-dir", ".zig-global-cache", "dump-bidi-properties"], cwd=ROOT.parent,
                                     stdout=output)
            if process.returncode:
                raise SystemExit("compiled bidi dump failed")
            output.seek(0)
            for cp in range(U21_LIMIT):
                actual = output.read(9)
                if cp < MAX_CP:
                    wanted_record = record(wanted[cp], mirrors.get(cp), brackets.get(cp))
                else:
                    wanted_record = record(0, None, None)
                if actual != wanted_record:
                    raise SystemExit(f"compiled bidi mismatch at 0x{cp:X}")
            if output.read(1):
                raise SystemExit("compiled bidi dump has trailing bytes")
    print(f"ok: {MAX_CP} generated bidi records" + (f" and {U21_LIMIT} compiled u21 records" if args.compiled else ""))


if __name__ == "__main__":
    main()
