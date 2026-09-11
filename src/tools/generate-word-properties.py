#!/usr/bin/env python3
"""Generate Unicode 17.0.0 word-segmentation property data.

Run from the repository root:
    python3 src/tools/generate-word-properties.py

This is a sibling of generate-properties.py, not an extension of it. The fused
`Record` cannot answer Word_Break: identical records occur for `"` and `'`, and
for `,` and `.`, despite different WB classes. So words get their own
compressed code-point table, and the existing records are left untouched.

Three facts per code point fit in one byte:

    Word_Break                5 bits
    Alphabetic OR GC=Number   1 bit
    Extended_Pictographic     1 bit   (WB3c)

Storing all three here avoids a second lookup into the fused record.
"""

from collections import defaultdict
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
OUT = ROOT / "tables/word_properties.zig"
FILES = {
    "wb": DATA / "WordBreakProperty-17.0.0.txt",
    "alpha": DATA / "DerivedCoreProperties-17.0.0.txt",
    "ep": DATA / "emoji-data-17.0.0.txt",
    "ud": DATA / "UnicodeData-17.0.0.txt",
}

MAXCP = 0x110000
BLOCK_SHIFT = 8
BLOCK_SIZE = 1 << BLOCK_SHIFT

# WordBreakProperty-17.0.0.txt carries "@missing: 0000..10FFFF; Other", so the
# default is Other and it is not listed. Every other value is read from the
# file rather than hardcoded, and the total is asserted below.
DEFAULT_WB = "Other"
NUMBER_CATEGORIES = ("Nd", "Nl", "No")


def parse(path, wanted=None):
    result = defaultdict(list)
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        left, prop = (part.strip() for part in line.split(";", 1))
        if wanted is not None and prop not in wanted:
            continue
        if ".." in left:
            lo, hi = (int(part, 16) for part in left.split("..", 1))
        else:
            lo = hi = int(left, 16)
        result[prop].append((lo, hi))
    return result


def dense_categories(path):
    out = ["Cn"] * MAXCP
    pending = None
    for line in path.read_text(encoding="utf-8").splitlines():
        fields = line.split(";")
        cp, name, category = int(fields[0], 16), fields[1], fields[2]
        if name.endswith(", First>"):
            pending = (cp, category)
        elif name.endswith(", Last>"):
            start, saved = pending
            for point in range(start, cp + 1):
                out[point] = saved
            pending = None
        else:
            out[cp] = category
    return out


def spread(values, default):
    out = [default] * MAXCP
    for prop, ranges in values.items():
        for lo, hi in ranges:
            for cp in range(lo, min(hi + 1, MAXCP)):
                out[cp] = prop
    return out


def zig_name(name):
    return re.sub(r"[^a-z0-9]", "_", name.lower())


def build(wb, alpha, ep, categories):
    names = [DEFAULT_WB] + sorted(wb)
    assert DEFAULT_WB not in wb, "the default must not also be listed"
    assert len(names) == 19, f"expected 19 occurring Word_Break values, got {len(names)}"
    assert len(names) <= 32, "Word_Break must fit in five bits"
    index = {name: i for i, name in enumerate(names)}

    wb_d = spread(wb, DEFAULT_WB)
    alpha_d = spread(alpha, "")
    ep_d = spread(ep, "")

    values = [0] * MAXCP
    for cp in range(MAXCP):
        word_like = alpha_d[cp] == "Alphabetic" or categories[cp] in NUMBER_CATEGORIES
        pictographic = ep_d[cp] == "Extended_Pictographic"
        values[cp] = index[wb_d[cp]] | (int(word_like) << 5) | (int(pictographic) << 6)
    return names, values


def emit(out, names, values):
    default = names.index(DEFAULT_WB)

    blocks, index = {}, []
    for base in range(0, MAXCP, BLOCK_SIZE):
        key = tuple(values[base:base + BLOCK_SIZE])
        index.append(blocks.setdefault(key, len(blocks)))
    assert len(blocks) < 65536

    out.write("//! Generated from pinned Unicode 17.0.0 UCD files. Do not edit.\n")
    out.write("//! Run src/tools/generate-word-properties.py to regenerate.\n")
    out.write("//!\n")
    out.write("//! Word segmentation keeps its own table rather than reading `properties.Record`:\n")
    out.write("//! the fused record cannot distinguish `\"` from `'`, or `,` from `.`, yet UAX #29\n")
    out.write("//! gives each of those pairs different Word_Break classes.\n\n")

    out.write("/// UAX #29 Word_Break property values occurring in Unicode 17.0.0.\n")
    out.write("pub const WordBreak = enum(u5) {\n")
    for name in names:
        out.write(f"    {zig_name(name)},\n")
    out.write("};\n\n")

    out.write("/// One byte per code point.\n")
    out.write("///\n")
    out.write("/// `word_like` is zunic's convenience predicate for `WordBound.is_word`,\n")
    out.write("/// not a UAX #29 rule input: `Alphabetic = Yes` or `General_Category` in\n")
    out.write("/// {Nd, Nl, No}. `extended_pictographic` is a rule input, for WB3c.\n")
    out.write("pub const WordProperties = packed struct(u8) {\n")
    out.write("    wb: WordBreak,\n")
    out.write("    word_like: bool,\n")
    out.write("    extended_pictographic: bool,\n")
    out.write("    _padding: u1 = 0,\n")
    out.write("};\n\n")

    out.write(f"pub const word_default: WordProperties = @bitCast(@as(u8, 0x{default:02X}));\n")
    out.write(f"pub const word_block_shift = {BLOCK_SHIFT};\n\n")

    out.write("pub const word_index = [_]u16{\n")
    for i in range(0, len(index), 16):
        out.write("    " + " ".join(f"{v}," for v in index[i:i + 16]) + "\n")
    out.write("};\n\n")

    flat = [value for key in sorted(blocks, key=blocks.get) for value in key]
    out.write("pub const word_data = [_]u8{\n")
    for i in range(0, len(flat), 16):
        out.write("    " + " ".join(f"0x{v:02X}," for v in flat[i:i + 16]) + "\n")
    out.write("};\n\n")

    out.write("/// Two dependent loads, matching the shape of `properties.record`.\n")
    out.write("pub fn wordProperties(cp: u21) WordProperties {\n")
    out.write(f"    if (cp >= 0x{MAXCP:X}) return word_default;\n")
    out.write("    const block = word_index[cp >> word_block_shift];\n")
    out.write("    const offset = (@as(usize, block) << word_block_shift) | (cp & (@as(usize, 1) << word_block_shift) - 1);\n")
    out.write("    return @bitCast(word_data[offset]);\n")
    out.write("}\n")

    return len(blocks), len(index), len(flat)


def main():
    wb = parse(FILES["wb"])
    alpha = parse(FILES["alpha"], {"Alphabetic"})
    ep = parse(FILES["ep"], {"Extended_Pictographic"})
    names, values = build(wb, alpha, ep, dense_categories(FILES["ud"]))
    with OUT.open("w", encoding="utf-8") as out:
        blocks, index_len, data_len = emit(out, names, values)
    # The repository keeps generated Zig formatted, and zig fmt column-aligns
    # array rows. Running it here rather than by hand keeps regeneration
    # byte-identical, which test-word-properties.py checks.
    zig = shutil.which("zig")
    if zig is None:
        sys.exit("zig is required to format the generated file")
    subprocess.run([zig, "fmt", str(OUT)], check=True, stdout=subprocess.DEVNULL)
    print(f"word_break values: {len(names)}")
    print(f"unique blocks:     {blocks}")
    print(f"index bytes:       {index_len * 2}")
    print(f"data bytes:        {data_len}")
    print(f"total bytes:       {index_len * 2 + data_len}")


if __name__ == "__main__":
    main()
