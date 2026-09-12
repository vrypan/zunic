#!/usr/bin/env python3
"""Generate simple Unicode 17 uppercase, lowercase, and titlecase mappings."""

import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "data/UnicodeData-17.0.0.txt"
DEFAULT_OUT = ROOT / "tables/simple_case_mappings.zig"
MAXCP = 0x110000
S1, S2 = 10, 4


def build():
    classes = {(0, 0, 0): 0}
    ids = bytearray(MAXCP)
    for raw in SOURCE.read_text(encoding="utf-8").splitlines():
        fields = raw.split(";")
        cp = int(fields[0], 16)
        mapping = tuple(int(fields[index], 16) - cp if fields[index] else 0
                        for index in (12, 13, 14))
        ids[cp] = classes.setdefault(mapping, len(classes))

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
    values = sorted(classes, key=classes.get)
    for mapping in values:
        assert all(-(1 << 16) <= delta < (1 << 16) for delta in mapping)
    return values, stage1, stage2, stage3


def emit(path):
    values, stage1, stage2, stage3 = build()
    with path.open("w", encoding="utf-8") as out:
        out.write("//! Generated from UnicodeData-17.0.0.txt; do not edit.\n")
        out.write("//! Run src/tools/generate-simple-case-mappings.py to regenerate.\n\n")
        out.write("const Mapping = packed struct(u64) { uppercase: i17, lowercase: i17, titlecase: i17, _padding: u13 = 0 };\n")
        out.write(f"const s1 = {S1};\nconst s2 = {S2};\n\n")
        for name, data, per_line in (
            ("stage1", stage1, 24),
            ("stage2", stage2, 24),
            ("stage3", stage3, 24),
        ):
            out.write(f"const {name} = [_]u8{{\n")
            for index in range(0, len(data), per_line):
                out.write("    " + " ".join(f"{value}," for value in data[index:index + per_line]) + "\n")
            out.write("};\n\n")
        out.write("const mappings = [_]Mapping{\n")
        for uppercase, lowercase, titlecase in values:
            out.write("    .{ .uppercase = %d, .lowercase = %d, .titlecase = %d },\n" %
                      (uppercase, lowercase, titlecase))
        out.write("};\n\n")
        out.write("pub const table_bytes: usize = @sizeOf(@TypeOf(stage1)) + @sizeOf(@TypeOf(stage2)) + @sizeOf(@TypeOf(stage3)) + @sizeOf(@TypeOf(mappings));\n\n")
        out.write("fn mapping(cp: u21) Mapping {\n")
        out.write("    if (cp > 0x10ffff) return .{ .uppercase = 0, .lowercase = 0, .titlecase = 0 };\n")
        out.write("    const mid = stage1[cp >> s1];\n")
        out.write("    const leaf = stage2[(@as(usize, mid) << (s1 - s2)) | (cp >> s2 & ((1 << (s1 - s2)) - 1))];\n")
        out.write("    const id = stage3[(@as(usize, leaf) << s2) | (cp & ((1 << s2) - 1))];\n")
        out.write("    return mappings[id];\n}\n\n")
        out.write("fn shifted(cp: u21, delta: i17) u21 {\n")
        out.write("    return @intCast(@as(i32, cp) + @as(i32, delta));\n}\n\n")
        out.write("pub fn simpleUppercase(cp: u21) u21 {\n")
        out.write("    if (cp >= 'a' and cp <= 'z') return cp - 0x20;\n")
        out.write("    return shifted(cp, mapping(cp).uppercase);\n}\n\n")
        out.write("pub fn simpleLowercase(cp: u21) u21 {\n")
        out.write("    if (cp >= 'A' and cp <= 'Z') return cp + 0x20;\n")
        out.write("    return shifted(cp, mapping(cp).lowercase);\n}\n\n")
        out.write("pub fn simpleTitlecase(cp: u21) u21 {\n")
        out.write("    if (cp >= 'a' and cp <= 'z') return cp - 0x20;\n")
        out.write("    return shifted(cp, mapping(cp).titlecase);\n}\n")
    trie_bytes = len(stage1) + len(stage2) + len(stage3)
    print(f"wrote {path}: {len(values)} mapping classes, {trie_bytes} trie bytes")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=DEFAULT_OUT)
    emit(parser.parse_args().output)


if __name__ == "__main__":
    main()
