#!/usr/bin/env python3
"""Generate simple Unicode 17 uppercase, lowercase, and titlecase mappings.

A shared two-stage index selects signed deltas directly, without a class
lookup. Each case operation has its own leaf array so unused operations do
not retain their payloads. ASCII uses the same lookup as other code points.
"""

import argparse
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "data/UnicodeData-17.0.0.txt"
DEFAULT_OUT = ROOT / "tables/simple_case_mappings.zig"
MAXCP = 0x110000
# 32-codepoint leaves minimize index + one operation's i32 payload for UCD 17.
SHIFT = 5


def build():
    mappings = {}
    for raw in SOURCE.read_text(encoding="utf-8").splitlines():
        fields = raw.split(";")
        cp = int(fields[0], 16)
        targets = tuple(int(fields[index], 16) if fields[index] else cp
                        for index in (12, 13, 14))
        assert all(0 <= target < MAXCP for target in targets)
        deltas = tuple(target - cp for target in targets)
        if any(deltas):
            mappings[cp] = deltas

    leaf_size = 1 << SHIFT
    limit = (max(mappings) + leaf_size) // leaf_size * leaf_size
    leaves, stage1 = {}, []
    for base in range(0, limit, leaf_size):
        row = tuple(mappings.get(cp, (0, 0, 0)) for cp in range(base, base + leaf_size))
        # Store offsets rather than block ids: no scaling after the first load.
        stage1.append(leaves.setdefault(row, len(leaves) * leaf_size))
    flat = [deltas for leaf in leaves for deltas in leaf]
    assert len(flat) <= 65536, "leaf offsets must fit u16"
    arrays = [[deltas[index] for deltas in flat] for index in range(3)]
    return limit, stage1, arrays


def emit(path):
    limit, stage1, arrays = build()
    with path.open("w", encoding="utf-8") as out:
        out.write("//! Generated from UnicodeData-17.0.0.txt; do not edit.\n")
        out.write("//! Run src/tools/generate-simple-case-mappings.py to regenerate.\n")
        out.write("//! Two dependent reads: shared leaf offsets, then an operation's signed delta.\n")
        out.write("//! Separate payload arrays let unused case operations stay out of the binary.\n\n")
        out.write(f"const shift = {SHIFT};\nconst limit = {limit};\n\n")
        for name, ty, data in (
            ("stage1", "u16", stage1),
            ("uppercase", "i32", arrays[0]),
            ("lowercase", "i32", arrays[1]),
            ("titlecase", "i32", arrays[2]),
        ):
            out.write(f"const {name} = [_]{ty}{{\n")
            for index in range(0, len(data), 16):
                out.write("    " + " ".join(f"{value}," for value in data[index:index + 16]) + "\n")
            out.write("};\n\n")
        out.write("pub const table_bytes: usize = @sizeOf(@TypeOf(stage1)) + @sizeOf(@TypeOf(uppercase)) + @sizeOf(@TypeOf(lowercase)) + @sizeOf(@TypeOf(titlecase));\n\n")
        out.write("""fn mapped(cp: u21, comptime deltas: []const i32) u21 {
    const value: u32 = cp;
    if (value >= limit) return cp;
    const offset = stage1[value >> shift];
    const index = @as(usize, offset) + (value & ((1 << shift) - 1));
    return @intCast(@as(i32, cp) + deltas[index]);
}

pub fn simpleUppercase(cp: u21) u21 {
    return mapped(cp, &uppercase);
}

pub fn simpleLowercase(cp: u21) u21 {
    return mapped(cp, &lowercase);
}

pub fn simpleTitlecase(cp: u21) u21 {
    return mapped(cp, &titlecase);
}
""")
    subprocess.run(["zig", "fmt", str(path)], check=True, stdout=subprocess.DEVNULL)
    shared_bytes = len(stage1) * 2
    payload_bytes = len(arrays[0]) * 4
    print(f"wrote {path}: {shared_bytes} shared index bytes, "
          f"{payload_bytes} bytes per case, {shared_bytes + payload_bytes * 3} bytes total")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUT)
    emit(parser.parse_args().output)


if __name__ == "__main__":
    main()
