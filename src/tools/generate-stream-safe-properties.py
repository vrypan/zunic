#!/usr/bin/env python3
"""Generate Unicode 16.0.0 stream-safe non-starter counts.

Run from the repository root:
    python3 src/tools/generate-stream-safe-properties.py
    python3 src/tools/generate-stream-safe-properties.py --check

UAX #15 section 13 defines Stream-Safe Text Format over the **NFKD** form:
"a Unicode string is said to be in Stream-Safe Text Format if it would not
contain any sequences of non-starters longer than 30 characters in length when
normalized to NFKD".

That is why this is a separate generator and a separate module. zunic publishes
only NFC and NFD, and `generate-normalization-properties.py` deliberately drops
the 3,832 compatibility mappings; its canonical counts cannot answer this
question. What is kept here is three small numbers per scalar, never the NFKD
transformation itself and never its mapping tables.

Keeping it in its own file also keeps it out of binaries that never ask for
stream-safe output.
"""

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
OUT = ROOT / "stream_safe_properties.zig"
UNICODE_DATA = DATA / "UnicodeData-16.0.0.txt"

MAXCP = 0x110000
LIMIT = 0x30000          # every scalar above this is trivial; asserted below
S1, S2 = 8, 3            # measured smallest of the shapes tried
STREAM_SAFE_LIMIT = 30   # UAX #15 section 13

S_BASE, L_BASE, V_BASE, T_BASE = 0xAC00, 0x1100, 0x1161, 0x11A7
L_COUNT, V_COUNT, T_COUNT = 19, 21, 28
N_COUNT = V_COUNT * T_COUNT
S_COUNT = L_COUNT * N_COUNT


def read_unicode_data():
    """Combining classes, and decomposition mappings *including* compatibility.

    The compatibility tag is dropped from the mapping but the mapping is kept,
    which is the difference from the canonical generator.
    """
    ccc, mapping = {}, {}
    for raw in UNICODE_DATA.read_text(encoding="utf-8").splitlines():
        fields = raw.split(";")
        cp = int(fields[0], 16)
        if int(fields[3]):
            ccc[cp] = int(fields[3])
        text = fields[5].strip()
        if text:
            parts = text.split()
            if parts[0].startswith("<"):
                parts = parts[1:]
            mapping[cp] = [int(part, 16) for part in parts]
    return ccc, mapping


def build_nfkd(mapping):
    cache = {}

    def nfkd(cp):
        if cp in cache:
            return cache[cp]
        if S_BASE <= cp < S_BASE + S_COUNT:
            index = cp - S_BASE
            out = [L_BASE + index // N_COUNT, V_BASE + (index % N_COUNT) // T_COUNT]
            if index % T_COUNT:
                out.append(T_BASE + index % T_COUNT)
        elif cp in mapping:
            out = []
            for part in mapping[cp]:
                out.extend(nfkd(part))
        else:
            out = [cp]
        cache[cp] = out
        return out

    return nfkd


def build(ccc, nfkd):
    """(leading, trailing, has_starter) per scalar, plus the safety checks."""
    def key(cp):
        parts = nfkd(cp)
        leading = 0
        for part in parts:
            if ccc.get(part, 0):
                leading += 1
            else:
                break
        trailing = 0
        for part in reversed(parts):
            if ccc.get(part, 0):
                trailing += 1
            else:
                break
        return leading, trailing, any(ccc.get(part, 0) == 0 for part in parts)

    classes, ids = {}, [0] * MAXCP
    worst_run = 0
    for cp in range(MAXCP):
        ids[cp] = classes.setdefault(key(cp), len(classes))
        run = 0
        for part in nfkd(cp):
            run = run + 1 if ccc.get(part, 0) else 0
            worst_run = max(worst_run, run)

    order = sorted(classes, key=classes.get)
    assert all(lead < 8 and trail < 8 for lead, trail, _ in order), "a count needs more than three bits"
    # Insertion happens only *before* a scalar, so a scalar whose own NFKD held
    # more than 30 consecutive non-starters could not be made stream safe at
    # all. Unicode 16 has no such scalar; assert it rather than assume it.
    assert worst_run <= STREAM_SAFE_LIMIT, \
        f"a single scalar's NFKD has {worst_run} consecutive non-starters, over the limit"
    # ASCII is uniform, so the runtime can answer it without touching memory.
    assert all(key(cp) == (0, 0, True) for cp in range(128)), "ASCII is no longer trivially stream safe"

    above = {ids[cp] for cp in range(LIMIT, MAXCP)}
    assert len(above) == 1, "the range above the trie is not a single class"

    leaf_size = 1 << S2
    leaves, mids, stage1 = {}, {}, []
    for base in range(0, LIMIT, 1 << S1):
        row = tuple(
            leaves.setdefault(tuple(ids[at:at + leaf_size]), len(leaves))
            for at in range(base, base + (1 << S1), leaf_size)
        )
        stage1.append(mids.setdefault(row, len(mids)))
    assert len(mids) < 256 and len(leaves) < 256 and len(classes) < 256, "an index needs more than a byte"
    stage2 = [leaf for row in sorted(mids, key=mids.get) for leaf in row]
    stage3 = [cid for leaf in sorted(leaves, key=leaves.get) for cid in leaf]
    return order, stage1, stage2, stage3, above.pop(), worst_run


def emit(out, order, stage1, stage2, stage3, above):
    out.write("//! Generated from pinned Unicode 16.0.0 UCD files. Do not edit.\n")
    out.write("//! Run src/tools/generate-stream-safe-properties.py to regenerate.\n")
    out.write("//!\n")
    out.write("//! Stream-Safe Text Format counts, from UAX #15 section 13. The standard\n")
    out.write("//! defines the format over **NFKD**, so these counts come from the full\n")
    out.write("//! compatibility decomposition even though zunic publishes only NFC and\n")
    out.write("//! NFD. Only the three counts are kept; no compatibility mapping is.\n")
    out.write("//!\n")
    out.write("//! Six distinct combinations occur over all 1,114,112 code points, and\n")
    out.write("//! 2,022 scalars are anything other than the trivial one.\n\n")

    out.write("/// What one scalar contributes to the non-starter run, measured on its\n")
    out.write("/// NFKD form. When `has_starter` is false every code point in that form\n")
    out.write("/// is a non-starter, so `leading` and `trailing` are both its length.\n")
    out.write("pub const Counts = packed struct(u8) {\n")
    out.write("    leading: u3,\n")
    out.write("    trailing: u3,\n")
    out.write("    has_starter: bool,\n")
    out.write("    _padding: u1 = 0,\n")
    out.write("};\n\n")

    out.write("/// The limit UAX #15 section 13 sets on consecutive non-starters.\n")
    out.write(f"pub const stream_safe_limit: usize = {STREAM_SAFE_LIMIT};\n")
    out.write("/// U+034F COMBINING GRAPHEME JOINER, inserted to break a long run.\n")
    out.write("pub const combining_grapheme_joiner: u21 = 0x034F;\n\n")

    packed = [lead | trail << 3 | int(starter) << 6 for lead, trail, starter in order]
    out.write("pub const class_table = [_]u8{\n    ")
    out.write(" ".join(f"0x{value:02X}," for value in packed))
    out.write("\n};\n\n")
    out.write(f"pub const class_limit: u21 = 0x{LIMIT:X};\n")
    out.write(f"pub const class_above_limit: u8 = {above};\n")
    out.write(f"const class_s1 = {S1};\n")
    out.write(f"const class_s2 = {S2};\n\n")
    for name, values in (("class_stage1", stage1), ("class_stage2", stage2), ("class_stage3", stage3)):
        out.write(f"pub const {name} = [_]u8{{\n")
        for i in range(0, len(values), 24):
            out.write("    " + " ".join(f"{v}," for v in values[i:i + 24]) + "\n")
        out.write("};\n\n")

    out.write("""/// ASCII carries no counts at all, so it answers without touching memory;
/// the generator asserts that uniformity against the data.
pub fn countsOf(cp: u21) Counts {
    if (cp < 128) return .{ .leading = 0, .trailing = 0, .has_starter = true };
    if (cp >= class_limit) return @bitCast(class_table[class_above_limit]);
    const mid = class_stage1[cp >> class_s1];
    const leaf = class_stage2[(@as(usize, mid) << (class_s1 - class_s2)) | (cp >> class_s2 & ((1 << (class_s1 - class_s2)) - 1))];
    return @bitCast(class_table[class_stage3[(@as(usize, leaf) << class_s2) | (cp & ((1 << class_s2) - 1))]]);
}
""")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--output", type=Path, default=OUT, help="destination for generated Zig")
    mode.add_argument("--check", action="store_true", help="compare without changing the generated source")
    args = parser.parse_args()
    zig = shutil.which("zig")
    if zig is None:
        sys.exit("zig is required to format the generated file")

    ccc, mapping = read_unicode_data()
    order, stage1, stage2, stage3, above, worst_run = build(ccc, build_nfkd(mapping))
    with tempfile.TemporaryDirectory() as tmp:
        generated = Path(tmp) / "stream_safe_properties.zig"
        with generated.open("w", encoding="utf-8") as out:
            emit(out, order, stage1, stage2, stage3, above)
        subprocess.run([zig, "fmt", str(generated)], check=True, stdout=subprocess.DEVNULL)
        if args.check:
            if not OUT.exists() or generated.read_bytes() != OUT.read_bytes():
                sys.exit("src/stream_safe_properties.zig is stale; run the generator")
        else:
            shutil.copyfile(generated, args.output)

    total = len(order) + len(stage1) + len(stage2) + len(stage3)
    print(f"classes            {len(order):6}")
    print(f"class_table        {len(order):6} B")
    print(f"class_stage1       {len(stage1):6} B")
    print(f"class_stage2       {len(stage2):6} B")
    print(f"class_stage3       {len(stage3):6} B")
    print(f"total              {total:6} B")
    print(f"worst NFKD non-starter run in one scalar: {worst_run} (limit {STREAM_SAFE_LIMIT})")


if __name__ == "__main__":
    main()
