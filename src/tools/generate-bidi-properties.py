#!/usr/bin/env python3
"""Generate Unicode 17 bidirectional codepoint property tables."""

import argparse
import hashlib
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
DEFAULT_OUT = ROOT / "tables/bidi_properties.zig"
MAX_CP = 0x110000
PAGE_SHIFT = 7
BIDI_ORDER = (
    "L", "LRE", "LRO", "R", "AL", "RLE", "RLO", "PDF", "EN", "ES", "ET",
    "AN", "CS", "NSM", "BN", "B", "S", "WS", "ON", "LRI", "RLI", "FSI",
    "PDI",
)
EXPECTED_HASHES = {
    "DerivedBidiClass-17.0.0.txt": "4867b4b7f0731ed1bfcd34cc6251211ff1542541fce0734b6fbda139ee80b3a4",
    "BidiMirroring-17.0.0.txt": "a2f16fb873ab4fcdf3221cb1a8a85a134ddd6ed03603181823ff5206af3741ce",
    "BidiBrackets-17.0.0.txt": "dadbaf38a0d0246e5b805bf8725cb81b7c621f93d030595635f5ba2c2f179428",
}


def records(path):
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.split("#", 1)[0].strip()
        if line:
            yield number, [field.strip() for field in line.split(";")]


def interval(text):
    fields = text.split("..", 1)
    lo, hi = int(fields[0], 16), int(fields[-1], 16)
    if lo > hi or hi >= MAX_CP:
        raise ValueError(f"invalid codepoint interval: {text}")
    return lo, hi


def zig_name(name):
    return re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", name.replace("-", "_")).lower()


def parse_aliases():
    aliases, names = {}, []
    for number, fields in records(DATA / "PropertyValueAliases-17.0.0.txt"):
        if fields[0] != "bc":
            continue
        if len(fields) < 3:
            raise ValueError(f"PropertyValueAliases:{number}: malformed bc alias")
        short, long_name = fields[1], fields[2]
        names.append((short, long_name))
        for alias in fields[1:]:
            if alias:
                previous = aliases.setdefault(alias, short)
                if previous != short:
                    raise ValueError(f"PropertyValueAliases:{number}: duplicate alias {alias}")
    if len(names) != 23 or not any(short == "L" for short, _ in names):
        raise ValueError("unexpected Unicode 17 Bidi_Class aliases")
    by_short = dict(names)
    if set(by_short) != set(BIDI_ORDER):
        raise ValueError("unexpected Unicode 17 Bidi_Class values")
    ordered = [(short, by_short[short]) for short in BIDI_ORDER]
    return aliases, ordered


def apply_range(dense, seen, lo, hi, value, label, reject_overlap):
    if reject_overlap and any(seen[lo:hi + 1]):
        raise ValueError(f"{label}: overlapping explicit ranges")
    dense[lo:hi + 1] = bytes([value]) * (hi - lo + 1)
    if reject_overlap:
        seen[lo:hi + 1] = b"\1" * (hi - lo + 1)


def parse_inputs():
    aliases, names = parse_aliases()
    ids = {short: value for value, (short, _) in enumerate(names)}
    derived = DATA / "DerivedBidiClass-17.0.0.txt"
    dense = bytearray([ids["L"]]) * MAX_CP
    seen = bytearray(MAX_CP)
    missing = []
    for number, raw in enumerate(derived.read_text(encoding="utf-8").splitlines(), 1):
        if raw.startswith("# @missing:"):
            fields = raw.split(":", 1)[1].split(";", 1)
            if len(fields) != 2 or fields[1].strip() not in aliases:
                raise ValueError(f"DerivedBidiClass:{number}: malformed @missing")
            lo, hi = interval(fields[0].strip())
            missing.append((lo, hi, ids[aliases[fields[1].strip()]]))
    if len(missing) != 24 or missing[0][:2] != (0, MAX_CP - 1):
        raise ValueError("unexpected Unicode 17 Bidi_Class defaults")
    for lo, hi, value in missing:
        apply_range(dense, seen, lo, hi, value, "@missing", False)
    explicit_count = 0
    for number, fields in records(derived):
        if len(fields) != 2 or fields[1] not in aliases:
            raise ValueError(f"DerivedBidiClass:{number}: malformed record")
        lo, hi = interval(fields[0])
        apply_range(dense, seen, lo, hi, ids[aliases[fields[1]]], "DerivedBidiClass", True)
        explicit_count += hi - lo + 1

    mirrored = bytearray(MAX_CP)
    range_start = None
    unicode_rows = 0
    for number, fields in records(DATA / "UnicodeData-17.0.0.txt"):
        if len(fields) != 15 or fields[4] not in ids or fields[9] not in ("Y", "N"):
            raise ValueError(f"UnicodeData:{number}: malformed bidi fields")
        cp = int(fields[0], 16)
        if fields[1].endswith(", First>"):
            if range_start is not None:
                raise ValueError("UnicodeData: nested First range")
            range_start = cp
            continue
        lo = range_start if fields[1].endswith(", Last>") else cp
        range_start = None
        if any(value != ids[fields[4]] for value in dense[lo:cp + 1]):
            raise ValueError(f"UnicodeData:{number}: Bidi_Class disagrees with DerivedBidiClass")
        mirrored[lo:cp + 1] = bytes([fields[9] == "Y"]) * (cp - lo + 1)
        unicode_rows += cp - lo + 1
    if range_start is not None:
        raise ValueError("UnicodeData: unterminated First range")

    def mappings(filename, fields_expected):
        result = {}
        for number, fields in records(DATA / filename):
            if len(fields) != fields_expected:
                raise ValueError(f"{filename}:{number}: malformed mapping")
            cp, target = int(fields[0], 16), int(fields[1], 16)
            if cp >= MAX_CP or target >= MAX_CP or cp in result:
                raise ValueError(f"{filename}:{number}: duplicate or invalid mapping")
            result[cp] = (target, fields[2]) if fields_expected == 3 else target
        return result

    mirrors = mappings("BidiMirroring-17.0.0.txt", 2)
    brackets = mappings("BidiBrackets-17.0.0.txt", 3)
    for cp, target in mirrors.items():
        if not mirrored[cp] or mirrors.get(target) != cp:
            raise ValueError(f"BidiMirroring: non-mirrored or non-reciprocal U+{cp:04X}")
    bracket_type = bytearray(MAX_CP)
    for cp, (target, kind) in brackets.items():
        if kind not in ("o", "c") or mirrors.get(cp) != target:
            raise ValueError(f"BidiBrackets: inconsistent mapping U+{cp:04X}")
        wanted = "c" if kind == "o" else "o"
        if brackets.get(target) != (cp, wanted) or dense[cp] != ids["ON"] or not mirrored[cp]:
            raise ValueError(f"BidiBrackets: inconsistent pair U+{cp:04X}")
        bracket_type[cp] = 1 if kind == "o" else 2

    combined = bytearray(value | (is_mirrored << 5) | (kind << 6)
                         for value, is_mirrored, kind in zip(dense, mirrored, bracket_type))
    if (explicit_count, sum(mirrored), len(mirrors), len(brackets), len(set(combined))) != (301169, 554, 428, 128, 26):
        raise ValueError("unexpected Unicode 17 bidi source shape")
    return names, combined, mirrors, brackets, unicode_rows


def two_stage(dense):
    page_size = 1 << PAGE_SHIFT
    pages, stage1 = {}, []
    for base in range(0, MAX_CP, page_size):
        page = bytes(dense[base:base + page_size])
        stage1.append(pages.setdefault(page, len(pages)))
    stage2 = [value for page in sorted(pages, key=pages.get) for value in page]
    if (len(stage1), len(pages), len(stage2)) != (8704, 191, 24448):
        raise ValueError("pinned bidi trie geometry changed")
    return stage1, stage2


def mapping_table(mappings, shift, expected_pages, label):
    dense = [0xFFFF] * 0x10000
    for cp, target in mappings.items():
        if cp > 0xFFFF or target > 0xFFFF:
            raise ValueError(f"{label} no longer fits the BMP table")
        dense[cp] = target
    page_size = 1 << shift
    pages, stage1 = {}, []
    for base in range(0, 0x10000, page_size):
        page = tuple(dense[base:base + page_size])
        stage1.append(pages.setdefault(page, len(pages)))
    stage2 = [value for page in sorted(pages, key=pages.get) for value in page]
    if (len(stage1), len(pages)) != (0x10000 >> shift, expected_pages):
        raise ValueError(f"pinned {label} trie geometry changed")
    return stage1, stage2


def emit_array(lines, name, ty, values, per_line=24, hexadecimal=False):
    lines.append(f"const {name} = [_]{ty}{{")
    for start in range(0, len(values), per_line):
        chunk = values[start:start + per_line]
        rendered = [f"0x{v:04X}" if hexadecimal else str(v) for v in chunk]
        lines.append("    " + ", ".join(rendered) + ",")
    lines.append("};")
    lines.append("")


def render():
    names, dense, mirrors, brackets, _ = parse_inputs()
    stage1, stage2 = two_stage(dense)
    mirror_stage1, mirror_stage2 = mapping_table(mirrors, 6, 29, "mirror")
    bracket_targets = {cp: value[0] for cp, value in brackets.items()}
    bracket_stage1, bracket_stage2 = mapping_table(bracket_targets, 6, 18, "bracket")
    lines = [
        "//! Generated from pinned Unicode 17.0.0 UCD files. Do not edit.",
        "//! Run src/tools/generate-bidi-properties.py to regenerate.", "",
        "pub const BidiClass = enum(u5) {",
    ]
    lines.extend(f"    {zig_name(long_name)} = {value}," for value, (_, long_name) in enumerate(names))
    lines += ["};", "", "pub const BidiPairedBracketType = enum(u2) { none = 0, open = 1, close = 2 };", "",
              "pub const BidiProperties = packed struct(u8) {", "    class: BidiClass,", "    isMirrored: bool,",
              "    pairedBracketType: BidiPairedBracketType,", "};", ""]
    emit_array(lines, "property_stage1", "u8", stage1)
    emit_array(lines, "property_stage2", "u8", stage2)
    emit_array(lines, "mirror_stage1", "u8", mirror_stage1)
    emit_array(lines, "mirror_stage2", "u16", mirror_stage2, 16, True)
    emit_array(lines, "bracket_stage1", "u8", bracket_stage1)
    emit_array(lines, "bracket_stage2", "u16", bracket_stage2, 16, True)
    lines += [
        "pub const properties_table_bytes = @sizeOf(@TypeOf(property_stage1)) + @sizeOf(@TypeOf(property_stage2));",
        "pub const mirrors_table_bytes = @sizeOf(@TypeOf(mirror_stage1)) + @sizeOf(@TypeOf(mirror_stage2));",
        "pub const brackets_table_bytes = @sizeOf(@TypeOf(bracket_stage1)) + @sizeOf(@TypeOf(bracket_stage2));",
        "pub const table_bytes = properties_table_bytes + mirrors_table_bytes + brackets_table_bytes;", "",
        "comptime {",
        "    if (@bitSizeOf(BidiProperties) != 8) @compileError(\"BidiProperties must remain one byte\");",
        "    if (properties_table_bytes != 33152 or mirrors_table_bytes != 4736 or brackets_table_bytes != 3328 or table_bytes != 41216) @compileError(\"bidi table sizes changed\");",
        "}", "",
        "pub fn properties(cp: u21) BidiProperties {",
        "    if (cp >= 0x110000) return .{ .class = .left_to_right, .isMirrored = false, .pairedBracketType = .none };",
        "    const page = property_stage1[cp >> 7];",
        "    return @bitCast(property_stage2[(@as(usize, page) << 7) | (cp & 127)]);",
        "}", "",
        "pub fn mirroringGlyph(cp: u21) ?u21 {",
        "    if (cp > 0xFFFF) return null;",
        "    const page = mirror_stage1[cp >> 6];",
        "    const value = mirror_stage2[(@as(usize, page) << 6) | (cp & 63)];",
        "    return if (value == 0xFFFF) null else @intCast(value);",
        "}",
        "pub fn pairedBracket(cp: u21) ?u21 {",
        "    if (cp > 0xFFFF) return null;",
        "    const page = bracket_stage1[cp >> 6];",
        "    const value = bracket_stage2[(@as(usize, page) << 6) | (cp & 63)];",
        "    return if (value == 0xFFFF) null else @intCast(value);",
        "}", "",
    ]
    return "\n".join(lines)


def check_inputs():
    for name, expected in EXPECTED_HASHES.items():
        actual = hashlib.sha256((DATA / name).read_bytes()).hexdigest()
        if actual != expected:
            raise ValueError(f"{name}: SHA-256 {actual}, expected {expected}")
    _, _, mirrors, brackets, assigned = parse_inputs()
    print(f"ok: 23 classes, 554 mirrored, {len(mirrors)} mirror mappings, {len(brackets)} bracket entries, {assigned} UnicodeData points")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--check-inputs", action="store_true")
    args = parser.parse_args()
    check_inputs()
    if not args.check_inputs:
        args.output.write_text(render(), encoding="utf-8")
        subprocess.run(["zig", "fmt", str(args.output)], check=True, stdout=subprocess.DEVNULL)


if __name__ == "__main__":
    main()
