#!/usr/bin/env python3
"""Generate Unicode 17.0.0 fused property records and ASCII lookup arrays.

Run from the repository root:
    python3 src/tools/generate-properties.py

The inputs are committed under ../data.  This script deliberately parses the
pinned UCD files instead of Python's Unicode database, whose version is not a
reproducible input.
"""

from collections import defaultdict
from pathlib import Path
import re

from line_break_categories import category_key as line_break_category_key

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
OUT = ROOT / "tables/properties.zig"
FILES = {
    "gcb": DATA / "GraphemeBreakProperty-17.0.0.txt",
    "ep": DATA / "emoji-data-17.0.0.txt",
    "lb": DATA / "LineBreak-17.0.0.txt",
    "incb": DATA / "DerivedCoreProperties-17.0.0.txt",
    "eaw": DATA / "EastAsianWidth-17.0.0.txt",
    "ud": DATA / "UnicodeData-17.0.0.txt",
}


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


def zig_name(name):
    return re.sub(r"[^a-z0-9]", "_", name.lower())


def value_at(values, point, default):
    for value, ranges in values.items():
        for lo, hi in ranges:
            if lo <= point <= hi:
                return value
    return default


def emit_grapheme_api(out, gcb, incb, ep):
    out.write("pub const GraphemeClass = enum(u4) { other, cr, lf, control, extend, zwj, regional_indicator, prepend, spacingmark, l, v, t, lv, lvt };\n")
    out.write("pub const IndicConjunctBreak = enum(u2) { none, consonant, extend, linker };\n")
    out.write("/// Bit-identical to the low 7 bits of Record, so graphemeOf is a truncate.\n")
    out.write("pub const GraphemeProperties = packed struct(u7) { gcb: GraphemeClass, incb: IndicConjunctBreak, extended_pictographic: bool };\n")
    out.write("pub const grapheme_ascii = [_]GraphemeProperties{\n")
    for cp in range(128):
        gcb_value = value_at(gcb, cp, "Other")
        incb_value = value_at(incb, cp, "None")
        pictographic = value_at(ep, cp, "") == "Extended_Pictographic"
        out.write(f"    .{{ .gcb = .{zig_name(gcb_value)}, .incb = .{zig_name(incb_value.replace('InCB; ', ''))}, .extended_pictographic = {'true' if pictographic else 'false'} }},\n")
    out.write("};\n\n")


def emit_line_break_api(out, values):
    names = sorted(values)
    out.write("pub const LineBreak = enum(u6) {\n")
    for name in names:
        out.write(f"    {zig_name(name)},\n")
    out.write("};\n\n")
    ranges = sorted((lo, hi, zig_name(name)) for name, entries in values.items() for lo, hi in entries)
    for left, right in zip(ranges, ranges[1:]):
        assert left[1] < right[0], (left, right)
    out.write("pub const line_break_ascii = [_]LineBreak{\n")
    for cp in range(128):
        out.write(f"    .{zig_name(value_at(values, cp, 'XX'))},\n")
    out.write("};\n\n")



MAXCP = 0x110000

# East_Asian_Width defaults for UNASSIGNED code points, from the header of
# EastAsianWidth-17.0.0.txt: everything unlisted is "N" except unassigned code
# points in these blocks, which default to "W".
EAW_DEFAULT_W = (
    (0x3400, 0x4DBF),    # CJK Unified Ideographs Extension A
    (0x4E00, 0x9FFF),    # CJK Unified Ideographs
    (0xF900, 0xFAFF),    # CJK Compatibility Ideographs
    (0x20000, 0x2FFFD),  # Plane 2
    (0x30000, 0x3FFFD),  # Plane 3
)

GCB_ORDER = ["Other", "CR", "LF", "Control", "Extend", "ZWJ", "Regional_Indicator",
             "Prepend", "SpacingMark", "L", "V", "T", "LV", "LVT"]
INCB_ORDER = ["None", "InCB; Consonant", "InCB; Extend", "InCB; Linker"]

# Bit layout of Record, mirrored by the packed struct emitted below. Zig packs
# from the least significant bit, so this order is the struct field order.
BIT_GCB, BIT_INCB, BIT_EP, BIT_LB, BIT_WIDTH, BIT_PRED, BIT_LB_CATEGORY = 0, 4, 6, 7, 13, 15, 23
PREDICATES = ["lb_op30", "lb_cp30", "lb_qu_pi", "lb_qu_pf", "lb_ba_hyphen",
              "lb_sa_mn_mc", "east_asian_wide", "ep_cn"]
BLOCK_SHIFT = 8
BLOCK_SIZE = 1 << BLOCK_SHIFT


def spread(values, default):
    """Expand range maps into a dense per-code-point array."""
    out = [default] * MAXCP
    for prop, ranges in values.items():
        for lo, hi in ranges:
            for cp in range(lo, min(hi + 1, MAXCP)):
                out[cp] = prop
    return out


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


def build_records(gcb, incb, ep, lb, eaw, categories, lb_names):
    """One packed record per code point, covering every fact any consumer reads."""
    gcb_d = spread(gcb, "Other")
    incb_d = spread(incb, "None")
    ep_d = spread(ep, "")
    lb_d = spread(lb, "XX")
    eaw_d = spread(eaw, "N")
    cat_d = categories

    for lo, hi in EAW_DEFAULT_W:
        for cp in range(lo, hi + 1):
            if eaw_d[cp] == "N" and cat_d[cp] == "Cn":
                eaw_d[cp] = "W"

    gcb_index = {name: i for i, name in enumerate(GCB_ORDER)}
    incb_index = {name: i for i, name in enumerate(INCB_ORDER)}
    lb_index = {name: i for i, name in enumerate(lb_names)}

    records = [0] * MAXCP
    for cp in range(MAXCP):
        category, lb_class = cat_d[cp], lb_d[cp]
        wide = eaw_d[cp] in ("W", "F", "H")
        pictographic = ep_d[cp] == "Extended_Pictographic"

        # Terminal cell width, applied in order: general category Mn/Me/Cf is
        # zero columns except U+00AD SOFT HYPHEN, which terminals draw; East
        # Asian Wide/Fullwidth is two; everything else is one. Surrogates
        # cannot appear in well-formed UTF-8 and are forced to one. This
        # replaces gen-width-table.py, which read Python's Unicode database
        # rather than the pinned UCD and so was not a reproducible input.
        if 0xD800 <= cp <= 0xDFFF:
            width = 1
        elif category in ("Mn", "Me", "Cf") and cp != 0x00AD:
            width = 0
        elif eaw_d[cp] in ("W", "F"):
            width = 2
        else:
            width = 1

        bits = [
            lb_class == "OP" and not wide,
            lb_class == "CP" and not wide,
            lb_class == "QU" and category == "Pi",
            lb_class == "QU" and category == "Pf",
            lb_class == "BA" and category == "Pd",
            lb_class == "SA" and category in ("Mn", "Mc"),
            wide,
            pictographic and category == "Cn",
        ]
        value = (gcb_index[gcb_d[cp]] << BIT_GCB) | (incb_index[incb_d[cp]] << BIT_INCB)
        value |= int(pictographic) << BIT_EP
        value |= lb_index[lb_class] << BIT_LB
        value |= width << BIT_WIDTH
        for offset, bit in enumerate(bits):
            value |= int(bit) << (BIT_PRED + offset)
        records[cp] = value

    # The semantic-machine category is an opaque internal acceleration field.
    # Its schema is the exact tuple consumed by line_break_semantics.py, and
    # first-scalar ordering makes the IDs deterministic from the pinned UCD.
    category_ids = {}
    scalar_order = list(range(0xD800)) + list(range(0xE000, MAXCP)) + list(range(0xD800, 0xE000))
    for cp in scalar_order:
        value = records[cp]
        raw = lb_d[cp]
        bits = tuple(bool(value & (1 << (BIT_PRED + offset))) for offset in range(len(PREDICATES)))
        key = line_break_category_key(
            raw, bits[6], bits[2] if raw == "QU" else False,
            bits[3] if raw == "QU" else False, bits[0] if raw == "OP" else False,
            bits[1] if raw == "CP" else False, bits[7], bits[5] if raw == "SA" else False,
            cp == 0x2010, cp == 0x25CC)
        category_id = category_ids.setdefault(key, len(category_ids))
        assert category_id < 128
        records[cp] = value | category_id << BIT_LB_CATEGORY
    malformed = line_break_category_key("AL")
    default = line_break_category_key("XX")
    return records, category_ids[malformed], category_ids[default]


def emit_record_table(out, records, lb_names, malformed_category, default_category):
    default = ((GCB_ORDER.index("Other") << BIT_GCB) | (lb_names.index("XX") << BIT_LB) |
               (1 << BIT_WIDTH) | (default_category << BIT_LB_CATEGORY))

    blocks, index = {}, []
    for base in range(0, MAXCP, BLOCK_SIZE):
        key = tuple(records[base:base + BLOCK_SIZE])
        index.append(blocks.setdefault(key, len(blocks)))
    assert len(blocks) < 65536

    out.write("/// Every fact any consumer derives from a code point, in one 32-bit\n")
    out.write("/// record. Zig packs from the least significant bit, so this field order\n")
    out.write("/// is the bit layout the generator writes.\n")
    out.write("pub const Record = packed struct(u32) {\n")
    out.write("    gcb: GraphemeClass,\n")
    out.write("    incb: IndicConjunctBreak,\n")
    out.write("    extended_pictographic: bool,\n")
    out.write("    line_break: LineBreak,\n")
    out.write("    width: u2,\n")
    for name in PREDICATES:
        out.write(f"    {name}: bool,\n")
    out.write("    line_break_category: u7,\n")
    out.write("    _padding: u2 = 0,\n")
    out.write("};\n\n")

    out.write(f"pub const line_break_malformed_category: u7 = {malformed_category};\n")
    out.write(f"pub const record_default: Record = @bitCast(@as(u32, 0x{default:X}));\n")
    out.write(f"pub const record_block_shift = {BLOCK_SHIFT};\n\n")

    out.write(f"pub const record_index = [_]u16{{\n")
    for i in range(0, len(index), 16):
        out.write("    " + " ".join(f"{v}," for v in index[i:i + 16]) + "\n")
    out.write("};\n\n")

    flat = [value for key in sorted(blocks, key=blocks.get) for value in key]
    out.write(f"pub const record_data = [_]u32{{\n")
    for i in range(0, len(flat), 8):
        out.write("    " + " ".join(f"0x{v:06X}," for v in flat[i:i + 8]) + "\n")
    out.write("};\n\n")

    out.write("/// Two dependent loads and no branching on data, replacing the range\n")
    out.write("/// binary searches this file used to emit.\n")
    out.write("pub fn record(cp: u21) Record {\n")
    out.write(f"    if (cp >= 0x{MAXCP:X}) return record_default;\n")
    out.write("    const block = record_index[cp >> record_block_shift];\n")
    out.write("    const offset = (@as(usize, block) << record_block_shift) | (cp & (@as(usize, 1) << record_block_shift) - 1);\n")
    out.write("    return @bitCast(record_data[offset]);\n")
    out.write("}\n\n")

    out.write("pub fn graphemeOf(r: Record) GraphemeProperties {\n")
    out.write("    return @bitCast(@as(u7, @truncate(@as(u32, @bitCast(r)))));\n}\n\n")
    out.write("pub fn graphemeProperties(cp: u21) GraphemeProperties { return graphemeOf(record(cp)); }\n\n")
    out.write("pub fn lineBreak(cp: u21) LineBreak { return record(cp).line_break; }\n")
    out.write("pub fn codepointWidth(cp: u21) u2 { return record(cp).width; }\n\n")
    for name, accessor in (("lb_op30", "isOp30"), ("lb_cp30", "isCp30"),
                           ("lb_qu_pi", "isQuPi"), ("lb_qu_pf", "isQuPf"),
                           ("lb_ba_hyphen", "isBaHyphen"), ("lb_sa_mn_mc", "isSaMnMc"),
                           ("east_asian_wide", "isEastAsianWide"),
                           ("ep_cn", "isExtendedPictographicCn")):
        out.write(f"pub fn {accessor}(cp: u21) bool {{ return record(cp).{name}; }}\n")


def main():
    gcb = parse(FILES["gcb"])
    ep = parse(FILES["ep"], {"Extended_Pictographic"})
    lb = parse(FILES["lb"])
    incb = parse(FILES["incb"], {"InCB; Consonant", "InCB; Extend", "InCB; Linker"})
    eaw = parse(FILES["eaw"])
    lb_names = sorted(lb)
    records, malformed_category, default_category = build_records(gcb, incb, ep, lb, eaw, dense_categories(FILES["ud"]), lb_names)
    with OUT.open("w", encoding="utf-8") as out:
        out.write("//! Generated from pinned Unicode 17.0.0 UCD files. Do not edit.\n")
        out.write("//! Run src/tools/generate-properties.py to regenerate.\n\n")
        emit_grapheme_api(out, gcb, incb, ep)
        emit_line_break_api(out, lb)
        emit_record_table(out, records, lb_names, malformed_category, default_category)


if __name__ == "__main__":
    main()
