#!/usr/bin/env python3
"""Generate Unicode 17 Script and Script_Extensions lookup tables."""

import argparse
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
DEFAULT_OUT = ROOT / "tables/script_properties.zig"
MAX_CP = 0x110000
PAGE_SHIFT = 7


def records(path):
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.split("#", 1)[0].strip()
        if line:
            yield number, [field.strip() for field in line.split(";")]


def interval(text):
    fields = text.split("..", 1)
    lo = int(fields[0], 16)
    hi = int(fields[-1], 16)
    if lo > hi or hi >= MAX_CP:
        raise ValueError(f"invalid codepoint interval: {text}")
    return lo, hi


def aliases(path):
    result = {}
    canonical = set()
    for number, fields in records(path):
        if fields[0] != "sc":
            continue
        if len(fields) < 3 or not fields[1] or not fields[2]:
            raise ValueError(f"{path}:{number}: malformed Script alias")
        long_name = fields[2]
        canonical.add(long_name)
        for alias in fields[1:]:
            if not alias:
                continue
            previous = result.setdefault(alias, long_name)
            if previous != long_name:
                raise ValueError(f"{path}:{number}: duplicate alias {alias}")
    return result, canonical


def parse_inputs():
    alias, known = aliases(DATA / "PropertyValueAliases-17.0.0.txt")
    script_ranges = []
    used = {"Unknown"}
    for number, fields in records(DATA / "Scripts-17.0.0.txt"):
        if len(fields) != 2 or fields[1] not in alias:
            raise ValueError(f"Scripts:{number}: malformed or unknown Script")
        lo, hi = interval(fields[0])
        name = alias[fields[1]]
        if name not in known:
            raise ValueError(f"Scripts:{number}: noncanonical Script")
        script_ranges.append((lo, hi, name))
        used.add(name)
    script_ranges.sort()
    for previous, current in zip(script_ranges, script_ranges[1:]):
        if current[0] <= previous[1]:
            raise ValueError("Scripts: overlapping ranges")

    extension_source = []
    for number, fields in records(DATA / "ScriptExtensions-17.0.0.txt"):
        if len(fields) != 2:
            raise ValueError(f"ScriptExtensions:{number}: malformed record")
        lo, hi = interval(fields[0])
        names = []
        for short in fields[1].split():
            if short not in alias:
                raise ValueError(f"ScriptExtensions:{number}: unknown Script {short}")
            names.append(alias[short])
        if not names or len(names) != len(set(names)):
            raise ValueError(f"ScriptExtensions:{number}: empty or duplicate member")
        used.update(names)
        extension_source.append((lo, hi, tuple(names)))
    extension_source.sort()
    for previous, current in zip(extension_source, extension_source[1:]):
        if current[0] <= previous[1]:
            raise ValueError("ScriptExtensions: overlapping ranges")

    if len(script_ranges) != 2287 or len(extension_source) != 206:
        raise ValueError("unexpected Unicode 17 source range counts")
    return script_ranges, extension_source, used


def zig_name(name):
    return re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", name.replace("-", "_")).lower()


def primary_table(ranges, ids):
    dense = bytearray(MAX_CP)
    for lo, hi, name in ranges:
        dense[lo:hi + 1] = bytes([ids[name]]) * (hi - lo + 1)
    page_size = 1 << PAGE_SHIFT
    pages = {}
    stage1 = []
    for base in range(0, MAX_CP, page_size):
        page = bytes(dense[base:base + page_size])
        stage1.append(pages.setdefault(page, len(pages)))
    stage2 = [value for page in sorted(pages, key=pages.get) for value in page]
    if (len(stage1), len(pages), len(stage2)) != (8704, 255, 32640):
        raise ValueError("pinned primary trie geometry changed")
    return stage1, stage2, len(pages)


def extension_table(source, ids):
    canonical = [(lo, hi, tuple(sorted((ids[name] for name in names)))) for lo, hi, names in source]
    merged = []
    for lo, hi, members in canonical:
        if merged and merged[-1][1] + 1 == lo and merged[-1][2] == members:
            merged[-1] = (merged[-1][0], hi, members)
        else:
            merged.append((lo, hi, members))
    sets = {}
    ranges = []
    for lo, hi, members in merged:
        set_id = sets.setdefault(members, len(sets))
        ranges.append((lo, hi - lo, set_id))
    ordered_sets = sorted(sets, key=sets.get)
    descriptors = []
    members = []
    for values in ordered_sets:
        descriptors.append((len(members), len(values)))
        members.extend(values)
    if (len(merged), len(ordered_sets), len(members)) != (176, 118, 536):
        raise ValueError("pinned Script_Extensions geometry changed")
    if max(length for _, length, _ in ranges) >= 64 or len(ordered_sets) >= 128:
        raise ValueError("extension range does not fit packed descriptor")
    if max(offset for offset, _ in descriptors) >= 1024 or max(length for _, length in descriptors) >= 32:
        raise ValueError("extension set does not fit packed descriptor")
    return ranges, descriptors, members


def write_values(out, values, render=str, width=16):
    for at in range(0, len(values), width):
        out.write("    " + " ".join(f"{render(value)}," for value in values[at:at + width]) + "\n")


def emit(path, names, stage1, stage2, ranges, descriptors, members):
    tags = [zig_name(name) for name in names]
    with path.open("w", encoding="utf-8") as out:
        out.write("//! Generated from pinned Unicode 17.0.0 UCD files. Do not edit.\n")
        out.write("//! Run src/tools/generate-script-properties.py to regenerate.\n\n")
        out.write("pub const Script = enum(u8) {\n")
        for tag in tags:
            out.write(f"    {tag},\n")
        out.write("};\n\n")
        out.write("const ExtensionRange = packed struct(u16) { length_minus_one: u6, set_id: u7, _padding: u3 = 0 };\n")
        out.write("const SetDescriptor = packed struct(u16) { offset: u10, len: u5, _padding: u1 = 0 };\n\n")
        out.write("const primary_stage1 = [_]u8{\n"); write_values(out, stage1, width=24); out.write("};\n\n")
        out.write("const primary_stage2 = [_]Script{\n"); write_values(out, stage2, lambda value: "." + tags[value], 12); out.write("};\n\n")
        out.write("const extension_starts = [_]u21{\n"); write_values(out, [lo for lo, _, _ in ranges], lambda value: f"0x{value:X}", 12); out.write("};\n\n")
        out.write("const extension_ranges = [_]ExtensionRange{\n")
        for _, length, set_id in ranges:
            out.write(f"    .{{ .length_minus_one = {length}, .set_id = {set_id} }},\n")
        out.write("};\n\nconst set_descriptors = [_]SetDescriptor{\n")
        for offset, length in descriptors:
            out.write(f"    .{{ .offset = {offset}, .len = {length} }},\n")
        out.write("};\n\nconst set_members = [_]Script{\n"); write_values(out, members, lambda value: "." + tags[value], 12); out.write("};\n\n")
        out.write("const singleton_values = [_]Script{\n"); write_values(out, range(len(tags)), lambda value: "." + tags[value], 12); out.write("};\n\n")
        out.write("pub const primary_table_bytes = @sizeOf(@TypeOf(primary_stage1)) + @sizeOf(@TypeOf(primary_stage2));\n")
        out.write("pub const extensions_table_bytes = @sizeOf(@TypeOf(extension_starts)) + @sizeOf(@TypeOf(extension_ranges)) + @sizeOf(@TypeOf(set_descriptors)) + @sizeOf(@TypeOf(set_members)) + @sizeOf(@TypeOf(singleton_values));\n")
        out.write("pub const table_bytes = primary_table_bytes + extensions_table_bytes;\n\n")
        out.write("comptime {\n    if (@typeInfo(Script).@\"enum\".fields.len != 175) @compileError(\"Script count changed\");\n    if (primary_table_bytes != 41344 or extensions_table_bytes != 2003 or table_bytes != 43347) @compileError(\"Script table sizes changed\");\n}\n\n")
        out.write("pub fn script(cp: u21) Script {\n")
        out.write("    if (cp >= 0x110000) return .unknown;\n")
        out.write("    const page = primary_stage1[cp >> 7];\n")
        out.write("    return primary_stage2[(@as(usize, page) << 7) | (cp & 127)];\n}\n\n")
        out.write("pub fn scriptExtensions(cp: u21) []const Script {\n")
        out.write("    if (cp >= 0x110000) return singleton_values[0..1];\n")
        out.write("    var low: usize = 0;\n    var high: usize = extension_starts.len;\n")
        out.write("    while (low < high) {\n        const middle = low + (high - low) / 2;\n        if (extension_starts[middle] <= cp) low = middle + 1 else high = middle;\n    }\n")
        out.write("    if (low != 0) {\n        const index = low - 1;\n        const item = extension_ranges[index];\n        const end = @as(u32, extension_starts[index]) + @as(u32, item.length_minus_one);\n        if (@as(u32, cp) <= end) {\n            const descriptor = set_descriptors[item.set_id];\n            const offset: usize = descriptor.offset;\n            return set_members[offset .. offset + descriptor.len];\n        }\n    }\n")
        out.write("    const id: usize = @intFromEnum(script(cp));\n    return singleton_values[id .. id + 1];\n}\n")


def diagnostic(ranges, ids):
    dense = bytearray(MAX_CP)
    for lo, hi, name in ranges:
        dense[lo:hi + 1] = bytes([ids[name]]) * (hi - lo + 1)
    choices = []
    for s1 in range(5, 14):
        for s2 in range(1, s1):
            leaves = {}
            mids = {}
            leaf_size = 1 << s2
            for base in range(0, MAX_CP, 1 << s1):
                row = tuple(leaves.setdefault(bytes(dense[p:p + leaf_size]), len(leaves)) for p in range(base, base + (1 << s1), leaf_size))
                mids.setdefault(row, len(mids))
            s1_width = 1 if len(mids) <= 256 else 2
            s2_width = 1 if len(leaves) <= 256 else 2
            size = (MAX_CP >> s1) * s1_width + len(mids) * (1 << (s1 - s2)) * s2_width + len(leaves) * leaf_size
            choices.append((size, s1, s2))
    best = min(choices)
    two_stage = []
    for shift in range(4, 13):
        page_size = 1 << shift
        pages = {bytes(dense[base:base + page_size]) for base in range(0, MAX_CP, page_size)}
        index_width = 1 if len(pages) <= 256 else 2
        size = (MAX_CP >> shift) * index_width + len(pages) * page_size
        two_stage.append((size, shift, len(pages), index_width))
    two_best = min(two_stage)
    if two_best != (41344, PAGE_SHIFT, 255, 1):
        raise ValueError("pinned two-stage geometry changed")
    print(f"three-stage geometry best: {best[0]} bytes at S1={best[1]}, S2={best[2]}")
    print(f"two-stage geometry best: {two_best[0]} bytes at page shift={two_best[1]}, {two_best[2]} pages, u{two_best[3] * 8} indices (selected)")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args()
    script_ranges, extension_source, used = parse_inputs()
    names = ["Unknown"] + sorted(used - {"Unknown"})
    if len(names) != 175 or len({zig_name(name) for name in names}) != len(names):
        raise ValueError("unexpected Script enum shape")
    ids = {name: index for index, name in enumerate(names)}
    stage1, stage2, pages = primary_table(script_ranges, ids)
    ranges, descriptors, members = extension_table(extension_source, ids)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    emit(args.output, names, stage1, stage2, ranges, descriptors, members)
    subprocess.run(["zig", "fmt", str(args.output)], check=True, stdout=subprocess.DEVNULL)
    diagnostic(script_ranges, ids)
    print(f"wrote {args.output}: {len(names)} scripts, {pages} primary pages, {len(ranges)} extension ranges")


if __name__ == "__main__":
    main()
