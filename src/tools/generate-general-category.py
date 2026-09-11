#!/usr/bin/env python3
"""Generate Unicode 16.0.0 General_Category and derived boolean properties.

Run from the repository root:
    python3 src/tools/generate-general-category.py

The inputs are committed under ../data. This script deliberately parses the
pinned UCD files instead of Python's Unicode database, whose version is not a
reproducible input.

This table is independent of `properties.zig`'s fused `Record`: nothing in
zunic's grapheme/line-break/word/wrap/normalization engines reads
General_Category, so widening `Record` to carry it would cost every existing
hot path for data most callers never touch. See plan 030.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
OUT = ROOT / "tables/general_category.zig"
MAXCP = 0x110000

GC_ORDER = [
    "Lu", "Ll", "Lt", "Lm", "Lo",
    "Mn", "Mc", "Me",
    "Nd", "Nl", "No",
    "Pc", "Pd", "Ps", "Pe", "Pi", "Pf", "Po",
    "Sm", "Sc", "Sk", "So",
    "Zs", "Zl", "Zp",
    "Cc", "Cf", "Cs", "Co", "Cn",
]
GC_ZIG_NAMES = {
    "Lu": "lu", "Ll": "ll", "Lt": "lt", "Lm": "lm", "Lo": "lo",
    "Mn": "mn", "Mc": "mc", "Me": "me",
    "Nd": "nd", "Nl": "nl", "No": "no_",
    "Pc": "pc", "Pd": "pd", "Ps": "ps", "Pe": "pe", "Pi": "pi", "Pf": "pf", "Po": "po",
    "Sm": "sm", "Sc": "sc", "Sk": "sk", "So": "so",
    "Zs": "zs", "Zl": "zl", "Zp": "zp",
    "Cc": "cc", "Cf": "cf", "Cs": "cs", "Co": "co", "Cn": "cn",
}

# name -> (source property, accessor). Order fixes the struct bit layout.
BOOLEANS = [
    ("Alphabetic", "is_alphabetic"),
    ("Lowercase", "is_lowercase"),
    ("Uppercase", "is_uppercase"),
    ("Cased", "is_cased"),
    ("Case_Ignorable", "is_case_ignorable"),
    ("Math", "is_math"),
    ("ID_Start", "is_id_start"),
    ("ID_Continue", "is_id_continue"),
    ("XID_Start", "is_xid_start"),
    ("XID_Continue", "is_xid_continue"),
    ("Default_Ignorable_Code_Point", "is_default_ignorable"),
    ("Grapheme_Base", "is_grapheme_base"),
    ("Grapheme_Extend", "is_grapheme_extend"),
]

# Chosen by exhaustive search over the actual generated class distribution
# (76 distinct classes); see plan 030. S1=9/S2=4 minimizes total trie bytes
# among block-shift pairs that keep every index within a reasonable width.
S1 = 9
S2 = 4


def dense_categories(path):
    """General_Category per code point, handling UnicodeData's <..., First>/
    <..., Last> range convention. Unlisted code points default to Cn."""
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


def dense_booleans(path, wanted):
    """One dense per-code-point bool array per wanted DerivedCoreProperties
    property name. Unlisted code points default to False."""
    out = {name: bytearray(MAXCP) for name in wanted}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        left, prop = (part.strip() for part in line.split(";", 1))
        if prop not in wanted:
            continue
        if ".." in left:
            lo, hi = (int(part, 16) for part in left.split("..", 1))
        else:
            lo = hi = int(left, 16)
        for cp in range(lo, min(hi + 1, MAXCP)):
            out[prop][cp] = 1
    return out


def build(categories, booleans):
    """One class per code point: the packed (category, *booleans) tuple,
    deduplicated. Most of the 1,114,112 code points share one of a small
    number of distinct combinations (76 today), the same shape plan 029's
    normalization Class table exploited.
    """
    names = [name for name, _ in BOOLEANS]

    def key(cp):
        return (categories[cp],) + tuple(booleans[name][cp] for name in names)

    classes, ids = {}, [0] * MAXCP
    for cp in range(MAXCP):
        ids[cp] = classes.setdefault(key(cp), len(classes))
    assert len(classes) < 256, "class id must fit a byte"
    order = sorted(classes, key=classes.get)

    leaf_size = 1 << S2
    leaves, mids, stage1 = {}, {}, []
    for base in range(0, MAXCP, 1 << S1):
        row = tuple(
            leaves.setdefault(tuple(ids[at:at + leaf_size]), len(leaves))
            for at in range(base, base + (1 << S1), leaf_size)
        )
        stage1.append(mids.setdefault(row, len(mids)))
    assert len(mids) < 256, "stage1 indices must fit a byte"

    stage2 = [leaf for row in sorted(mids, key=mids.get) for leaf in row]
    stage3 = [cid for leaf in sorted(leaves, key=leaves.get) for cid in leaf]
    assert all(leaf < 65536 for leaf in stage2), "stage2 indices must fit a u16"
    return order, stage1, stage2, stage3, ids[MAXCP - 1]


def emit(out, order, stage1, stage2, stage3, default_id):
    out.write("//! Generated from pinned Unicode 16.0.0 UCD files. Do not edit.\n")
    out.write("//! Run src/tools/generate-general-category.py to regenerate.\n")
    out.write("//!\n")
    out.write("//! Independent of `properties.Record`: see this file's generator for why.\n\n")

    out.write("pub const GeneralCategory = enum(u5) {\n")
    for name in GC_ORDER:
        out.write(f"    {GC_ZIG_NAMES[name]},\n")
    out.write("};\n\n")

    out.write("/// General_Category plus a fixed set of DerivedCoreProperties booleans, one\n")
    out.write("/// fused lookup. Zig packs from the least significant bit, so this field\n")
    out.write("/// order is the bit layout the generator writes.\n")
    out.write("pub const GeneralCategoryProperties = packed struct(u32) {\n")
    out.write("    category: GeneralCategory,\n")
    for _, accessor in BOOLEANS:
        out.write(f"    {accessor}: bool,\n")
    used = 5 + len(BOOLEANS)
    out.write(f"    _padding: u{32 - used} = 0,\n")
    out.write("};\n\n")

    out.write(f"const gc_s1 = {S1};\n")
    out.write(f"const gc_s2 = {S2};\n\n")

    out.write("pub const class_table = [_]GeneralCategoryProperties{\n")
    for combo in order:
        category = combo[0]
        bits = combo[1:]
        fields = [f".category = .{GC_ZIG_NAMES[category]}"]
        fields += [f".{accessor} = {'true' if bit else 'false'}" for (_, accessor), bit in zip(BOOLEANS, bits)]
        out.write("    .{ " + ", ".join(fields) + " },\n")
    out.write("};\n\n")

    out.write(f"pub const class_default: GeneralCategoryProperties = class_table[{default_id}];\n\n")

    out.write("pub const gc_stage1 = [_]u8{\n")
    for i in range(0, len(stage1), 24):
        out.write("    " + " ".join(f"{v}," for v in stage1[i:i + 24]) + "\n")
    out.write("};\n\n")

    out.write("pub const gc_stage2 = [_]u16{\n")
    for i in range(0, len(stage2), 24):
        out.write("    " + " ".join(f"{v}," for v in stage2[i:i + 24]) + "\n")
    out.write("};\n\n")

    out.write("pub const gc_stage3 = [_]u8{\n")
    for i in range(0, len(stage3), 24):
        out.write("    " + " ".join(f"{v}," for v in stage3[i:i + 24]) + "\n")
    out.write("};\n\n")

    out.write("/// Three dependent loads: block, leaf, class id, then one table read for\n")
    out.write("/// every General_Category and derived-boolean fact at once.\n")
    out.write("pub fn generalCategoryProperties(cp: u21) GeneralCategoryProperties {\n")
    out.write(f"    if (cp >= 0x{MAXCP:X}) return class_default;\n")
    out.write("    const mid = gc_stage1[cp >> gc_s1];\n")
    out.write("    const leaf = gc_stage2[(@as(usize, mid) << (gc_s1 - gc_s2)) | (cp >> gc_s2 & ((1 << (gc_s1 - gc_s2)) - 1))];\n")
    out.write("    const id = gc_stage3[(@as(usize, leaf) << gc_s2) | (cp & ((1 << gc_s2) - 1))];\n")
    out.write("    return class_table[id];\n")
    out.write("}\n\n")

    out.write("pub fn generalCategory(cp: u21) GeneralCategory {\n")
    out.write("    return generalCategoryProperties(cp).category;\n}\n\n")
    for _, accessor in BOOLEANS:
        out.write(f"pub fn {accessor}(cp: u21) bool {{ return generalCategoryProperties(cp).{accessor}; }}\n")


def main():
    categories = dense_categories(DATA / "UnicodeData-16.0.0.txt")
    booleans = dense_booleans(DATA / "DerivedCoreProperties-16.0.0.txt", {name for name, _ in BOOLEANS})
    order, stage1, stage2, stage3, default_id = build(categories, booleans)
    with OUT.open("w", encoding="utf-8") as out:
        emit(out, order, stage1, stage2, stage3, default_id)
    print(f"wrote {OUT}: {len(order)} classes, {len(stage1)} stage1, {len(stage2)} stage2, {len(stage3)} stage3")


if __name__ == "__main__":
    main()
