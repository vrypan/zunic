#!/usr/bin/env python3
"""Independently verify generated Script tables against the pinned UCD."""

import bisect
import filecmp
import re
import subprocess
import sys
import tempfile
from pathlib import Path

from check_unicode_version import check as check_unicode_version

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
SOURCE = ROOT / "tables/script_properties.zig"
GENERATOR = ROOT / "tools/generate-script-properties.py"
MAX_CP = 0x110000


def source_records(path):
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if line:
            yield [field.strip() for field in line.split(";")]


def interval(text):
    parts = text.split("..")
    return int(parts[0], 16), int(parts[-1], 16)


def section(text, declaration):
    match = re.search(rf"{re.escape(declaration)}\{{(.*?)\n\}};", text, re.S)
    if not match:
        raise SystemExit(f"cannot parse generated {declaration}")
    return match.group(1)


def numeric_array(text, name):
    body = section(text, f"const {name} = [_]u" + ("21" if name == "extension_starts" else "16" if name == "primary_stage2" else "8"))
    return [int(value, 0) for value in re.findall(r"0x[0-9A-F]+|\d+", body)]


def script_array(text, name, tag_ids):
    body = section(text, f"const {name} = [_]Script")
    return [tag_ids[tag] for tag in re.findall(r"\.(\w+)", body)]


def main():
    check_unicode_version(
        "Scripts-17.0.0.txt",
        "ScriptExtensions-17.0.0.txt",
        "PropertyValueAliases-17.0.0.txt",
    )
    with tempfile.TemporaryDirectory() as directory:
        generated = Path(directory) / "script_properties.zig"
        subprocess.run([sys.executable, str(GENERATOR), "--output", str(generated)], check=True, stdout=subprocess.DEVNULL)
        if not filecmp.cmp(generated, SOURCE, shallow=False):
            raise SystemExit("generated Script table is stale")

    aliases = {}
    for fields in source_records(DATA / "PropertyValueAliases-17.0.0.txt"):
        if fields[0] == "sc":
            for alias in fields[1:]:
                if alias:
                    aliases[alias] = fields[2]

    text = SOURCE.read_text(encoding="utf-8")
    enum_body = re.search(r"pub const Script = enum\(u8\) \{(.*?)\n\};", text, re.S).group(1)
    tags = re.findall(r"^\s+(\w+),$", enum_body, re.M)
    if len(tags) != 175 or tags[0] != "unknown":
        raise SystemExit("unexpected generated Script enum")
    tag_ids = {tag: value for value, tag in enumerate(tags)}

    def tag(name):
        converted = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", name.replace("-", "_")).lower()
        if converted not in tag_ids:
            raise SystemExit(f"source Script {name} is absent from the enum")
        return tag_ids[converted]

    expected_primary = bytearray(MAX_CP)
    script_count = 0
    for fields in source_records(DATA / "Scripts-17.0.0.txt"):
        lo, hi = interval(fields[0])
        expected_primary[lo:hi + 1] = bytes([tag(aliases[fields[1]])]) * (hi - lo + 1)
        script_count += 1
    if script_count != 2287:
        raise SystemExit(f"unexpected Scripts source count: {script_count}")

    expected_extensions = {}
    extension_count = 0
    extension_points = 0
    for fields in source_records(DATA / "ScriptExtensions-17.0.0.txt"):
        lo, hi = interval(fields[0])
        members = tuple(sorted(tag(aliases[name]) for name in fields[1].split()))
        for cp in range(lo, hi + 1):
            expected_extensions[cp] = members
        extension_count += 1
        extension_points += hi - lo + 1
    if extension_count != 206 or extension_points != 669:
        raise SystemExit(f"unexpected ScriptExtensions source shape: {extension_count} ranges, {extension_points} points")

    stage1 = numeric_array(text, "primary_stage1")
    stage2 = script_array(text, "primary_stage2", tag_ids)
    starts = numeric_array(text, "extension_starts")
    ranges_body = section(text, "const extension_ranges = [_]ExtensionRange")
    ranges = [(int(length), int(set_id)) for length, set_id in re.findall(r"length_minus_one = (\d+), \.set_id = (\d+)", ranges_body)]
    descriptor_body = section(text, "const set_descriptors = [_]SetDescriptor")
    descriptors = [(int(offset), int(length)) for offset, length in re.findall(r"offset = (\d+), \.len = (\d+)", descriptor_body)]
    members = script_array(text, "set_members", tag_ids)
    singletons = script_array(text, "singleton_values", tag_ids)
    if (len(stage1), len(stage2), len(starts), len(ranges), len(descriptors), len(members), len(singletons)) != (8704, 32640, 176, 176, 118, 536, 175):
        raise SystemExit("generated Script table counts changed")
    if singletons != list(range(175)):
        raise SystemExit("singleton table does not follow enum ordinals")

    for cp in range(MAX_CP):
        page = stage1[cp >> 7]
        primary = stage2[(page << 7) | (cp & 127)]
        if primary != expected_primary[cp]:
            raise SystemExit(f"Script mismatch at U+{cp:04X}: {tags[primary]} != {tags[expected_primary[cp]]}")

        index = bisect.bisect_right(starts, cp) - 1
        if index >= 0 and cp <= starts[index] + ranges[index][0]:
            offset, length = descriptors[ranges[index][1]]
            actual_extensions = tuple(members[offset:offset + length])
        else:
            actual_extensions = (primary,)
        wanted_extensions = expected_extensions.get(cp, (expected_primary[cp],))
        if actual_extensions != wanted_extensions:
            actual_names = tuple(tags[value] for value in actual_extensions)
            wanted_names = tuple(tags[value] for value in wanted_extensions)
            raise SystemExit(f"Script_Extensions mismatch at U+{cp:04X}: {actual_names} != {wanted_names}")

    print(f"ok: {MAX_CP} Script and Script_Extensions records verified")


if __name__ == "__main__":
    main()
