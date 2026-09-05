#!/usr/bin/env python3
"""Generate Unicode 16.0.0 grapheme and line-break lookup ranges.

Run from the repository root:
    python3 src/tools/generate-properties.py

The inputs are committed under ../data.  This script deliberately parses the
pinned UCD files instead of Python's Unicode database, whose version is not a
reproducible input.
"""

from collections import defaultdict
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
OUT = ROOT / "properties.zig"
FILES = {
    "gcb": DATA / "GraphemeBreakProperty-16.0.0.txt",
    "ep": DATA / "emoji-data-16.0.0.txt",
    "lb": DATA / "LineBreak-16.0.0.txt",
    "incb": DATA / "DerivedCoreProperties-16.0.0.txt",
    "eaw": DATA / "EastAsianWidth-16.0.0.txt",
    "ud": DATA / "UnicodeData-16.0.0.txt",
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


def emit_table(out, prefix, values):
    for prop in sorted(values):
        out.write(f"pub const {prefix}_{zig_name(prop)} = [_]Range{{\n")
        for lo, hi in values[prop]:
            out.write(f"    .{{ .lo = 0x{lo:X}, .hi = 0x{hi:X} }},\n")
        out.write("};\n\n")


def value_at(values, point, default):
    for value, ranges in values.items():
        for lo, hi in ranges:
            if lo <= point <= hi:
                return value
    return default


def partition_properties(gcb, incb, ep):
    boundaries = {0, 0x110000}
    for values in (gcb, incb, ep):
        for ranges in values.values():
            for lo, hi in ranges:
                boundaries.add(lo)
                boundaries.add(hi + 1)
    points = sorted(point for point in boundaries if point <= 0x110000)
    result = []
    for lo, end in zip(points, points[1:]):
        hi = end - 1
        gcb_value = value_at(gcb, lo, "Other")
        incb_value = value_at(incb, lo, "None")
        pictographic = value_at(ep, lo, "") == "Extended_Pictographic"
        if gcb_value != "Other" or incb_value != "None" or pictographic:
            result.append((lo, hi, gcb_value, incb_value, pictographic))
    for left, right in zip(result, result[1:]):
        assert left[1] < right[0]
    return result


def emit_grapheme_api(out, gcb, incb, ep):
    ranges = partition_properties(gcb, incb, ep)
    out.write("pub const GraphemeClass = enum { other, cr, lf, control, extend, zwj, regional_indicator, prepend, spacingmark, l, v, t, lv, lvt };\n")
    out.write("pub const IndicConjunctBreak = enum { none, consonant, extend, linker };\n")
    out.write("pub const GraphemeProperties = struct { gcb: GraphemeClass, incb: IndicConjunctBreak, extended_pictographic: bool };\n")
    out.write("pub const GraphemeRange = struct { lo: u21, hi: u21, properties: GraphemeProperties };\n\n")
    out.write("pub const grapheme_ranges = [_]GraphemeRange{\n")
    for lo, hi, gcb_value, incb_value, pictographic in ranges:
        out.write(f"    .{{ .lo = 0x{lo:X}, .hi = 0x{hi:X}, .properties = .{{ .gcb = .{zig_name(gcb_value)}, .incb = .{zig_name(incb_value.replace('InCB; ', ''))}, .extended_pictographic = {'true' if pictographic else 'false'} }} }},\n")
    out.write("};\n\n")
    out.write("pub const grapheme_ascii = [_]GraphemeProperties{\n")
    for cp in range(128):
        gcb_value = value_at(gcb, cp, "Other")
        incb_value = value_at(incb, cp, "None")
        pictographic = value_at(ep, cp, "") == "Extended_Pictographic"
        out.write(f"    .{{ .gcb = .{zig_name(gcb_value)}, .incb = .{zig_name(incb_value.replace('InCB; ', ''))}, .extended_pictographic = {'true' if pictographic else 'false'} }},\n")
    out.write("};\n\n")
    out.write("pub fn graphemeProperties(cp: u21) GraphemeProperties {\n")
    out.write("    if (cp < grapheme_ascii.len) return grapheme_ascii[cp];\n")
    out.write("    var lo: usize = 0; var hi: usize = grapheme_ranges.len;\n")
    out.write("    while (lo < hi) { const mid = lo + (hi - lo) / 2; const r = grapheme_ranges[mid]; if (cp < r.lo) hi = mid else if (cp > r.hi) lo = mid + 1 else return r.properties; }\n")
    out.write("    return .{ .gcb = .other, .incb = .none, .extended_pictographic = false };\n}\n\n")


def emit_line_break_api(out, values):
    names = sorted(values)
    out.write("pub const LineBreak = enum {\n")
    for name in names:
        out.write(f"    {zig_name(name)},\n")
    out.write("};\n\n")
    ranges = sorted((lo, hi, zig_name(name)) for name, entries in values.items() for lo, hi in entries)
    for left, right in zip(ranges, ranges[1:]):
        assert left[1] < right[0], (left, right)
    out.write("pub const LineBreakRange = struct { lo: u21, hi: u21, class: LineBreak };\n")
    out.write("pub const line_break_ranges = [_]LineBreakRange{\n")
    for lo, hi, name in ranges:
        out.write(f"    .{{ .lo = 0x{lo:X}, .hi = 0x{hi:X}, .class = .{name} }},\n")
    out.write("};\n\n")
    out.write("pub const line_break_ascii = [_]LineBreak{\n")
    for cp in range(128):
        out.write(f"    .{zig_name(value_at(values, cp, 'XX'))},\n")
    out.write("};\n\n")
    out.write("pub fn lineBreak(cp: u21) LineBreak {\n")
    out.write("    if (cp < line_break_ascii.len) return line_break_ascii[cp];\n")
    out.write("    var lo: usize = 0; var hi: usize = line_break_ranges.len;\n")
    out.write("    while (lo < hi) { const mid = lo + (hi - lo) / 2; const r = line_break_ranges[mid]; if (cp < r.lo) hi = mid else if (cp > r.hi) lo = mid + 1 else return r.class; }\n")
    out.write("    return .xx;\n}\n\n")
    out.write("fn inRanges(ranges: []const Range, cp: u21) bool {\n")
    out.write("    var lo: usize = 0;\n    var hi: usize = ranges.len;\n")
    out.write("    while (lo < hi) {\n        const mid = lo + (hi - lo) / 2;\n")
    out.write("        const r = ranges[mid];\n")
    out.write("        if (cp < r.lo) hi = mid else if (cp > r.hi) lo = mid + 1 else return true;\n")
    out.write("    }\n    return false;\n}\n")


def lookup(ranges, cp, default):
    for lo, hi, value in ranges:
        if lo <= cp <= hi:
            return value
    return default


def unicode_categories(path):
    values, pending = {}, None
    for line in path.read_text(encoding="utf-8").splitlines():
        fields = line.split(";")
        cp, name, category = int(fields[0], 16), fields[1], fields[2]
        if name.endswith(", First>"):
            pending = (cp, category)
        elif name.endswith(", Last>"):
            start, saved_category = pending
            for point in range(start, cp + 1):
                values[point] = saved_category
            pending = None
        else:
            values[cp] = category
    return values


def emit_tailoring(out, lb, eaw, categories):
    eaw_ranges = [(lo, hi, prop) for prop, ranges in eaw.items() for lo, hi in ranges]
    special = defaultdict(list)
    for prop in ("OP", "CP", "QU", "BA"):
        for lo, hi in lb[prop]:
            for cp in range(lo, hi + 1):
                east_asian = lookup(eaw_ranges, cp, "N") in {"W", "F", "H"}
                category = categories.get(cp, "Cn")
                if prop == "OP" and not east_asian:
                    special["op30"].append(cp)
                if prop == "CP" and not east_asian:
                    special["cp30"].append(cp)
                if prop == "QU" and category == "Pi":
                    special["qu_pi"].append(cp)
                if prop == "QU" and category == "Pf":
                    special["qu_pf"].append(cp)
                if prop == "BA" and category == "Pd":
                    special["ba_hyphen"].append(cp)
    for name in sorted(special):
        ranges = []
        for cp in special[name]:
            if ranges and cp == ranges[-1][1] + 1:
                ranges[-1] = (ranges[-1][0], cp)
            else:
                ranges.append((cp, cp))
        out.write(f"pub const lb_{name} = [_]Range{{\n")
        for lo, hi in ranges:
            out.write(f"    .{{ .lo = 0x{lo:X}, .hi = 0x{hi:X} }},\n")
        out.write("};\n\n")
    out.write("pub fn isOp30(cp: u21) bool { return inRanges(&lb_op30, cp); }\n")
    out.write("pub fn isCp30(cp: u21) bool { return inRanges(&lb_cp30, cp); }\n")
    out.write("pub fn isQuPi(cp: u21) bool { return inRanges(&lb_qu_pi, cp); }\n")
    out.write("pub fn isQuPf(cp: u21) bool { return inRanges(&lb_qu_pf, cp); }\n\n")
    out.write("pub fn isBaHyphen(cp: u21) bool { return inRanges(&lb_ba_hyphen, cp); }\n\n")


def coalesce(points):
    ranges = []
    for cp in points:
        if ranges and cp == ranges[-1][1] + 1:
            ranges[-1] = (ranges[-1][0], cp)
        else:
            ranges.append((cp, cp))
    return ranges


def emit_predicate(out, name, ranges):
    out.write(f"pub const {name}_ranges = [_]Range{{\n")
    for lo, hi in ranges:
        out.write(f"    .{{ .lo = 0x{lo:X}, .hi = 0x{hi:X} }},\n")
    out.write("};\n\n")
    out.write(f"pub fn {name}(cp: u21) bool {{ return inRanges(&{name}_ranges, cp); }}\n\n")


def emit_line_break_auxiliaries(out, lb, eaw, ep, categories):
    # LB1 resolves South East Asian marks as CM.  The test must be based on
    # the pinned UnicodeData category rather than Python's Unicode version.
    sa_mn_mc = []
    for lo, hi in lb["SA"]:
        sa_mn_mc.extend(cp for cp in range(lo, hi + 1) if categories.get(cp, "Cn") in {"Mn", "Mc"})
    emit_predicate(out, "isSaMnMc", coalesce(sa_mn_mc))

    # LB19a, LB21a, and LB30 consult East Asian F/W/H. LB30b also needs
    # unassigned Extended_Pictographic. Keep both binary-searchable at runtime.
    east_asian_wide = []
    for prop in ("F", "W", "H"):
        for lo, hi in eaw[prop]:
            east_asian_wide.extend(range(lo, hi + 1))
    emit_predicate(out, "isEastAsianWide", coalesce(sorted(east_asian_wide)))

    ep_cn = []
    for lo, hi in ep["Extended_Pictographic"]:
        ep_cn.extend(cp for cp in range(lo, hi + 1) if categories.get(cp, "Cn") == "Cn")
    emit_predicate(out, "isExtendedPictographicCn", coalesce(ep_cn))


def main():
    gcb = parse(FILES["gcb"])
    ep = parse(FILES["ep"], {"Extended_Pictographic"})
    lb = parse(FILES["lb"])
    incb = parse(FILES["incb"], {"InCB; Consonant", "InCB; Extend", "InCB; Linker"})
    eaw = parse(FILES["eaw"])
    categories = unicode_categories(FILES["ud"])
    with OUT.open("w", encoding="utf-8") as out:
        out.write("//! Generated from pinned Unicode 16.0.0 UCD files. Do not edit.\n")
        out.write("//! Run src/tools/generate-properties.py to regenerate.\n\n")
        out.write("pub const Range = struct { lo: u21, hi: u21 };\n\n")
        emit_table(out, "gcb", gcb)
        emit_table(out, "emoji", ep)
        emit_table(out, "lb", lb)
        emit_table(out, "incb", incb)
        emit_grapheme_api(out, gcb, incb, ep)
        emit_tailoring(out, lb, eaw, categories)
        emit_line_break_auxiliaries(out, lb, eaw, ep, categories)
        emit_line_break_api(out, lb)


if __name__ == "__main__":
    main()
