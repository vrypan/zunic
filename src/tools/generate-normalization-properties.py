#!/usr/bin/env python3
"""Generate Unicode 16.0.0 canonical normalization tables.

Run from the repository root:
    python3 src/tools/generate-normalization-properties.py
    python3 src/tools/generate-normalization-properties.py --check

A third sibling of generate-properties.py and generate-word-properties.py.
Normalization gets its own module for the same reason word segmentation did:
`properties.Record` is a full u32 with two padding bits, and a combining class
alone needs eight.

The data is extremely sparse -- 3,092 of 1,114,112 code points carry any of
these facts -- so a two-stage trie of the kind properties.zig uses costs more
in index than the payload is worth (measured at design time: 42 KB for a
u16 info index at the best block size, against 27 KB for the whole of this
layout). These tables are sorted arrays searched by bisection instead. The
lookups are O(log n) with n at most 2,081, and the engine skips them entirely
for the ASCII range, which carries no combining class and no decomposition.

Hangul composition and decomposition are algorithmic and deliberately absent
from every table here; the engine handles them arithmetically.
"""

import argparse
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
OUT = ROOT / "normalization_properties.zig"
FILES = {
    "ud": DATA / "UnicodeData-16.0.0.txt",
    "dnp": DATA / "DerivedNormalizationProps-16.0.0.txt",
    "exclusions": DATA / "CompositionExclusions-16.0.0.txt",
}

MAXCP = 0x110000
# Hangul, from UAX #15 section 16. Repeated in the engine; the two are checked
# against each other by the fixture.
S_BASE, L_BASE, V_BASE, T_BASE = 0xAC00, 0x1100, 0x1161, 0x11A7
L_COUNT, V_COUNT, T_COUNT = 19, 21, 28
N_COUNT = V_COUNT * T_COUNT
S_COUNT = L_COUNT * N_COUNT


def read_unicode_data():
    """Canonical combining class and canonical decomposition mapping."""
    ccc, decomposition = {}, {}
    for raw in FILES["ud"].read_text(encoding="utf-8").splitlines():
        fields = raw.split(";")
        cp = int(fields[0], 16)
        if int(fields[3]):
            ccc[cp] = int(fields[3])
        mapping = fields[5].strip()
        # A leading <tag> marks a compatibility mapping, which NFC and NFD
        # never apply. Those 3,832 mappings are deliberately dropped.
        if mapping and not mapping.startswith("<"):
            decomposition[cp] = [int(part, 16) for part in mapping.split()]
    return ccc, decomposition


def read_derived():
    """Full_Composition_Exclusion and the two canonical quick-check properties."""
    full, nfc_qc, nfd_qc = set(), {}, {}
    for raw in FILES["dnp"].read_text(encoding="utf-8").splitlines():
        body = raw.split("#", 1)[0].strip()
        if not body:
            continue
        parts = [part.strip() for part in body.split(";")]
        first, _, last = parts[0].partition("..")
        points = range(int(first, 16), (int(last, 16) if last else int(first, 16)) + 1)
        if parts[1] == "Full_Composition_Exclusion":
            full.update(points)
        elif parts[1] == "NFC_QC":
            for cp in points:
                nfc_qc[cp] = parts[2]
        elif parts[1] == "NFD_QC":
            for cp in points:
                nfd_qc[cp] = parts[2]
    return full, nfc_qc, nfd_qc


def utf8_len(cp):
    return 1 if cp < 0x80 else 2 if cp < 0x800 else 3 if cp < 0x10000 else 4


def decompose_hangul(cp):
    if not S_BASE <= cp < S_BASE + S_COUNT:
        return None
    index = cp - S_BASE
    out = [L_BASE + index // N_COUNT, V_BASE + (index % N_COUNT) // T_COUNT]
    if index % T_COUNT:
        out.append(T_BASE + index % T_COUNT)
    return out


def recursive(decomposition, cp):
    """Full canonical decomposition of one code point."""
    hangul = decompose_hangul(cp)
    if hangul is not None:
        return hangul
    if cp not in decomposition:
        return [cp]
    out = []
    for part in decomposition[cp]:
        out.extend(recursive(decomposition, part))
    return out


def derive_expansion_factor(decomposition, pairs):
    """The worst UTF-8 growth of NFD and NFC, in bytes out per byte in.

    Measure decomposition growth and verify that every eligible composition
    pair is byte-nonincreasing. Together these bound NFC as well as NFD.
    Singletons are excluded from composition: NFC maps KELVIN SIGN to "K",
    never the reverse. An excluded musical symbol witnesses NFC's 3x growth.
    """
    worst_nfd, nfd_witness = 1.0, None
    for cp in list(decomposition) + [S_BASE, S_BASE + 1]:
        grew = sum(utf8_len(part) for part in recursive(decomposition, cp)) / utf8_len(cp)
        if grew > worst_nfd:
            worst_nfd, nfd_witness = grew, cp

    for cp in pairs:
        assert utf8_len(cp) <= sum(utf8_len(part) for part in decomposition[cp]), \
            f"composition into U+{cp:04X} grows in bytes; revisit the NFC bound"
    # Algorithmic Hangul compositions also only shrink: L+V is 6 -> 3 bytes
    # and LV+T is 6 -> 3 bytes.
    nfc_witness = 0x1D160
    parts = recursive(decomposition, nfc_witness)
    assert parts == [0x1D158, 0x1D165, 0x1D16E]
    composition_pairs = {tuple(decomposition[cp]) for cp in pairs}
    assert all((a, b) not in composition_pairs for a in parts for b in parts)
    worst_nfc = sum(utf8_len(part) for part in parts) / utf8_len(nfc_witness)
    assert worst_nfd == worst_nfc == 3.0, "revisit the canonical expansion bound"
    return worst_nfd, nfd_witness, worst_nfc, nfc_witness, 3


def build(ccc, decomposition, full, nfc_qc):
    combining = sorted(ccc.items())
    assert all(cp < 1 << 18 for cp, _ in combining), "combining source needs more than 18 bits"
    assert all(value < 256 for _, value in combining)

    sources = sorted(decomposition)
    assert all(cp < 1 << 18 for cp in sources), "decomposition source needs more than 18 bits"
    assert all(len(decomposition[cp]) in (1, 2) for cp in sources), "immediate mapping is not 1 or 2"
    assert full <= set(sources), "an excluded character has no canonical decomposition"

    flat, offsets = [], {}
    for cp in sources:
        offsets[cp] = len(flat)
        flat.extend(decomposition[cp])
    assert len(flat) < 1 << 12, "decomposition data needs more than a 12-bit offset"
    assert all(part < 1 << 21 for part in flat)

    # Composition pairs: exactly the immediate two-scalar decompositions whose
    # source is not Full_Composition_Exclusion. Singletons are never reversed,
    # and recursively flattened forms are never used.
    pairs = {cp for cp in sources if len(decomposition[cp]) == 2 and cp not in full}
    seen = {}
    for cp in pairs:
        key = tuple(decomposition[cp])
        assert key not in seen, f"pair {key} maps to both U+{seen[key]:04X} and U+{cp:04X}"
        seen[key] = cp
    order = sorted(pairs, key=lambda cp: tuple(decomposition[cp]))
    composition = [sources.index(cp) for cp in order]
    assert all(index < 1 << 16 for index in composition)

    maybe = sorted(cp for cp, value in nfc_qc.items() if value == "M")
    return combining, sources, flat, offsets, composition, maybe, pairs


def emit(out, combining, sources, decomposition, flat, offsets, full, composition, maybe, factor):
    out.write("//! Generated from pinned Unicode 16.0.0 UCD files. Do not edit.\n")
    out.write("//! Run src/tools/generate-normalization-properties.py to regenerate.\n")
    out.write("//!\n")
    out.write("//! Canonical normalization only: NFC and NFD. The 3,832 compatibility\n")
    out.write("//! mappings in UnicodeData are deliberately absent, so nothing here can\n")
    out.write("//! answer an NFKC or NFKD question.\n")
    out.write("//!\n")
    out.write("//! Only 3,092 code points carry any of these facts, so these are sorted\n")
    out.write("//! arrays searched by bisection rather than the two-stage trie\n")
    out.write("//! properties.zig uses: at this density the trie's index alone costs more\n")
    out.write("//! than this entire layout. Hangul is algorithmic and appears in no table.\n\n")

    out.write("pub const QuickCheck = enum { yes, no, maybe };\n\n")
    assert combining[0][0] >= 0x80, "the ASCII shortcut in the engine assumes no combining marks below U+0080"

    out.write("/// Sorted by code point. Bits: `cp:u18 | ccc:u8 | unused:u6`.\n")
    out.write(f"pub const combining_entries = [_]u32{{\n")
    for i in range(0, len(combining), 8):
        row = " ".join(f"0x{(cp | value << 18):08X}," for cp, value in combining[i:i + 8])
        out.write("    " + row + "\n")
    out.write("};\n\n")

    out.write("/// Sorted by code point. Bits:\n")
    out.write("/// `cp:u18 | offset:u12 | is_pair:u1 | composition_excluded:u1`.\n")
    out.write("///\n")
    out.write("/// `offset` indexes `decomposition_data`; the mapping is the *immediate*\n")
    out.write("/// one, one scalar or two. Composition needs the immediate pair, and the\n")
    out.write("/// engine recurses for the full form, so storing the flattened mapping\n")
    out.write("/// would lose information rather than save work.\n")
    out.write(f"pub const decomposition_entries = [_]u32{{\n")
    values = []
    for cp in sources:
        word = cp | offsets[cp] << 18
        if len(decomposition[cp]) == 2:
            word |= 1 << 30
        if cp in full:
            word |= 1 << 31
        values.append(word)
    for i in range(0, len(values), 8):
        out.write("    " + " ".join(f"0x{v:08X}," for v in values[i:i + 8]) + "\n")
    out.write("};\n\n")

    out.write("/// Immediate canonical decomposition targets, one scalar per entry.\n")
    out.write(f"pub const decomposition_data = [_]u32{{\n")
    for i in range(0, len(flat), 8):
        out.write("    " + " ".join(f"0x{v:06X}," for v in flat[i:i + 8]) + "\n")
    out.write("};\n\n")

    out.write("/// Indices into `decomposition_entries`, ordered by the pair each entry\n")
    out.write("/// decomposes to, so a composition lookup bisects on `(first, second)`.\n")
    out.write(f"pub const composition_index = [_]u16{{\n")
    for i in range(0, len(composition), 16):
        out.write("    " + " ".join(f"{v}," for v in composition[i:i + 16]) + "\n")
    out.write("};\n\n")

    out.write("/// Sorted code points whose `NFC_QC` is Maybe. `NFC_QC = No` is exactly\n")
    out.write("/// `Full_Composition_Exclusion`, which the decomposition entry carries.\n")
    out.write(f"pub const nfc_qc_maybe = [_]u32{{\n")
    for i in range(0, len(maybe), 12):
        out.write("    " + " ".join(f"0x{v:06X}," for v in maybe[i:i + 12]) + "\n")
    out.write("};\n\n")

    worst_nfd, nfd_witness, worst_nfc, nfc_witness, emitted = factor
    out.write("/// Worst-case UTF-8 growth of either canonical form, in output bytes per\n")
    out.write("/// input byte, derived from the pinned data during generation.\n")
    out.write("///\n")
    out.write(f"/// NFD reaches {worst_nfd:.1f}x at U+{nfd_witness:04X} and at every Hangul LVT syllable,\n")
    out.write("/// which is three bytes in and three three-byte jamo out. NFC reaches\n")
    out.write(f"/// {worst_nfc:.1f}x at U+{nfc_witness:04X}: an excluded musical symbol decomposes from\n")
    out.write("/// four bytes to twelve. Eligible compositions are verified not to grow\n")
    out.write("/// UTF-8 byte length, so NFD's bound also bounds NFC.\n")
    out.write(f"pub const expansion_factor: usize = {emitted};\n\n")

    out.write('const std = @import("std");\n\n')
    out.write("/// Lowest code point carrying each fact, so the common case leaves before\n")
    out.write("/// bisecting anything. Derived, not assumed: nothing here knows that\n")
    out.write("/// U+0300 happens to be the first combining mark, and the whole of ASCII\n")
    out.write("/// sits below all three.\n")
    out.write(f"pub const first_combining: u21 = 0x{combining[0][0]:04X};\n")
    out.write(f"pub const first_decomposition: u21 = 0x{sources[0]:04X};\n")
    out.write(f"pub const first_nfc_relevant: u21 = 0x{min(sources[0], maybe[0]):04X};\n")
    out.write("/// Lowest code point that is ever the *second* half of a primary\n")
    out.write("/// composite. Nothing below it can compose with anything, which takes\n")
    out.write("/// every pair of ASCII characters out of the composition search.\n")
    lowest_second = min(decomposition[cp][1] for cp in sources
                        if len(decomposition[cp]) == 2 and cp not in full)
    out.write(f"pub const first_composable: u21 = 0x{lowest_second:04X};\n\n")
    out.write("""fn search(entries: []const u32, cp: u21, comptime mask: u32) ?usize {
    var low: usize = 0;
    var high: usize = entries.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        const key = entries[middle] & mask;
        if (key < cp) low = middle + 1 else if (key > cp) high = middle else return middle;
    }
    return null;
}

/// Canonical_Combining_Class. Zero for everything not in the table, which is
/// every starter and every unassigned code point.
pub fn combiningClass(cp: u21) u8 {
    if (cp < first_combining) return 0;
    const found = search(&combining_entries, cp, 0x3FFFF) orelse return 0;
    return @intCast(combining_entries[found] >> 18 & 0xFF);
}

pub const Decomposition = struct {
    /// One or two scalars: the immediate canonical mapping, not the recursive one.
    scalars: []const u32,
    /// `Full_Composition_Exclusion`: NFC must never rebuild this character.
    excluded: bool,
};

/// The immediate canonical decomposition of `cp`, or null if it has none.
/// Hangul syllables are absent; the engine decomposes them arithmetically.
pub fn decomposition(cp: u21) ?Decomposition {
    if (cp < first_decomposition) return null;
    const found = search(&decomposition_entries, cp, 0x3FFFF) orelse return null;
    const entry = decomposition_entries[found];
    const offset = entry >> 18 & 0xFFF;
    const len: usize = if (entry >> 30 & 1 == 1) 2 else 1;
    return .{
        .scalars = decomposition_data[offset..][0..len],
        .excluded = entry >> 31 & 1 == 1,
    };
}

/// The primary composite of `first` and `second`, if the pair has one that is
/// not excluded from composition. Hangul is handled by the engine.
pub fn compose(first: u21, second: u21) ?u21 {
    if (second < first_composable) return null;
    var low: usize = 0;
    var high: usize = composition_index.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        const entry = decomposition_entries[composition_index[middle]];
        const pair = decomposition_data[entry >> 18 & 0xFFF ..][0..2];
        // Lexicographic on (first, second), which is the order
        // composition_index is built in.
        const order = if (pair[0] != first)
            std.math.order(pair[0], first)
        else
            std.math.order(pair[1], second);
        switch (order) {
            .lt => low = middle + 1,
            .gt => high = middle,
            .eq => return @intCast(entry & 0x3FFFF),
        }
    }
    return null;
}

/// `NFC_QC`. No is exactly `Full_Composition_Exclusion`; Maybe has its own table.
pub fn nfcQuickCheck(cp: u21) QuickCheck {
    if (cp < first_nfc_relevant) return .yes;
    if (search(&nfc_qc_maybe, cp, 0x1FFFFF) != null) return .maybe;
    const found = search(&decomposition_entries, cp, 0x3FFFF) orelse return .yes;
    return if (decomposition_entries[found] >> 31 & 1 == 1) .no else .yes;
}

/// `NFD_QC`, which is two-valued. False means the code point decomposes.
/// Hangul syllables decompose and are not in the table, so the engine tests
/// them before calling this.
pub fn nfdQuickCheckIsYes(cp: u21) bool {
    if (cp < first_decomposition) return true;
    return search(&decomposition_entries, cp, 0x3FFFF) == null;
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
    ccc, decomposition = read_unicode_data()
    full, nfc_qc, _ = read_derived()
    combining, sources, flat, offsets, composition, maybe, pairs = build(ccc, decomposition, full, nfc_qc)
    factor = derive_expansion_factor(decomposition, pairs)
    with tempfile.TemporaryDirectory() as tmp:
        generated = Path(tmp) / "normalization_properties.zig"
        with generated.open("w", encoding="utf-8") as out:
            emit(out, combining, sources, decomposition, flat, offsets, full, composition, maybe, factor)
        subprocess.run([zig, "fmt", str(generated)], check=True, stdout=subprocess.DEVNULL)
        if args.check:
            if not OUT.exists() or generated.read_bytes() != OUT.read_bytes():
                sys.exit("src/normalization_properties.zig is stale; run the generator")
        else:
            shutil.copyfile(generated, args.output)

    sizes = {
        "combining_entries": len(combining) * 4,
        "decomposition_entries": len(sources) * 4,
        "decomposition_data": len(flat) * 4,
        "composition_index": len(composition) * 2,
        "nfc_qc_maybe": len(maybe) * 4,
    }
    for name, size in sizes.items():
        print(f"{name:24} {size:6} B")
    print(f"{'total':24} {sum(sizes.values()):6} B of 32768")
    print(f"expansion factor         {factor[4]} (NFD {factor[0]:.2f}x at U+{factor[1]:04X}, "
          f"NFC {factor[2]:.2f}x at U+{factor[3]:04X})")


if __name__ == "__main__":
    main()
