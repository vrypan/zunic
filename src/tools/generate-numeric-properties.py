#!/usr/bin/env python3
"""Generate exact Unicode 17 numeric values from UnicodeData.txt."""

import argparse
from fractions import Fraction
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "data/UnicodeData-17.0.0.txt"
DEFAULT_OUT = ROOT / "tables/numeric_properties.zig"
MAXCP = 0x110000
S1, S2 = 10, 5


def build():
    classes = {(None, None): 0}
    ids = bytearray(MAXCP)
    for raw in SOURCE.read_text(encoding="utf-8").splitlines():
        fields = raw.split(";")
        cp = int(fields[0], 16)
        if fields[6]:
            kind, value = "decimal", fields[6]
        elif fields[7]:
            kind, value = "digit", fields[7]
        elif fields[8]:
            kind, value = "numeric", fields[8]
        else:
            continue
        fraction = Fraction(value)
        assert -(1 << 63) <= fraction.numerator < (1 << 63)
        assert 0 < fraction.denominator < (1 << 16)
        ids[cp] = classes.setdefault((kind, fraction), len(classes))

    leaf_size = 1 << S2
    leaves, mids, stage1 = {}, {}, []
    for base in range(0, MAXCP, 1 << S1):
        row = tuple(
            leaves.setdefault(bytes(ids[at : at + leaf_size]), len(leaves))
            for at in range(base, base + (1 << S1), leaf_size)
        )
        stage1.append(mids.setdefault(row, len(mids)))
    assert len(classes) <= 256 and len(mids) <= 256 and len(leaves) <= 256
    stage2 = [leaf for row in sorted(mids, key=mids.get) for leaf in row]
    stage3 = [value for leaf in sorted(leaves, key=leaves.get) for value in leaf]
    ordered = sorted(classes, key=classes.get)[1:]
    return ordered, stage1, stage2, stage3


def emit(path):
    classes, stage1, stage2, stage3 = build()
    with path.open("w", encoding="utf-8") as out:
        out.write("//! Generated from UnicodeData-17.0.0.txt; do not edit.\n")
        out.write("//! Run src/tools/generate-numeric-properties.py to regenerate.\n\n")
        out.write("pub const NumericType = enum(u2) { decimal, digit, numeric };\n")
        out.write("pub const Numeric = struct { kind: NumericType, numerator: i64, denominator: u16 };\n")
        out.write(f"const s1 = {S1};\nconst s2 = {S2};\n\n")
        for name, zig_type, values, per_line in (
            ("stage1", "u8", stage1, 24),
            ("stage2", "u8", stage2, 24),
            ("stage3", "u8", stage3, 24),
        ):
            out.write(f"const {name} = [_]{zig_type}{{\n")
            for i in range(0, len(values), per_line):
                out.write("    " + " ".join(f"{value}," for value in values[i:i + per_line]) + "\n")
            out.write("};\n\n")
        out.write("const values = [_]Numeric{\n")
        for kind, value in classes:
            out.write(f"    .{{ .kind = .{kind}, .numerator = {value.numerator}, .denominator = {value.denominator} }},\n")
        out.write("};\n\n")
        out.write("pub const table_bytes: usize = @sizeOf(@TypeOf(stage1)) + @sizeOf(@TypeOf(stage2)) + @sizeOf(@TypeOf(stage3)) + @sizeOf(@TypeOf(values));\n\n")
        out.write("pub fn numeric(cp: u21) ?Numeric {\n")
        out.write("    if (cp > 0x10ffff) return null;\n")
        out.write("    const mid = stage1[cp >> s1];\n")
        out.write("    const leaf = stage2[(@as(usize, mid) << (s1 - s2)) | (cp >> s2 & ((1 << (s1 - s2)) - 1))];\n")
        out.write("    const id = stage3[(@as(usize, leaf) << s2) | (cp & ((1 << s2) - 1))];\n")
        out.write("    return if (id == 0) null else values[id - 1];\n}\n")
    print(f"wrote {path}: {len(classes)} values, {len(stage1) + len(stage2) + len(stage3)} trie bytes")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=DEFAULT_OUT)
    emit(parser.parse_args().output)


if __name__ == "__main__":
    main()
