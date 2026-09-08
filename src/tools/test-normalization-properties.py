#!/usr/bin/env python3
"""Exhaustively verify the generated canonical normalization tables.

Run from the repository root:
    python3 src/tools/test-normalization-properties.py

Independent by construction: it re-derives every fact from the pinned UCD files
and decodes src/normalization_properties.zig by parsing the emitted Zig,
sharing no classification code with the generator. A mismatch means the
generator is wrong; it is never something to patch in the output.

It also re-runs the generator into a temporary location and compares bytes, so
a nondeterministic generator fails here rather than producing a different table
on the next regeneration.
"""

import filecmp
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
SOURCE = ROOT / "normalization_properties.zig"
GENERATOR = ROOT / "tools" / "generate-normalization-properties.py"
FIXTURE = DATA / "NormalizationTest-16.0.0.txt"
MAXCP = 0x110000

S_BASE, L_BASE, V_BASE, T_BASE = 0xAC00, 0x1100, 0x1161, 0x11A7
L_COUNT, V_COUNT, T_COUNT = 19, 21, 28
N_COUNT = V_COUNT * T_COUNT
S_COUNT = L_COUNT * N_COUNT


def read_unicode_data():
    ccc, mapping = {}, {}
    for raw in (DATA / "UnicodeData-16.0.0.txt").read_text(encoding="utf-8").splitlines():
        parts = raw.split(";")
        cp = int(parts[0], 16)
        if int(parts[3]):
            ccc[cp] = int(parts[3])
        text = parts[5].strip()
        if text and "<" not in text:
            mapping[cp] = [int(item, 16) for item in text.split()]
    return ccc, mapping


def read_derived(name):
    values = {}
    for raw in (DATA / "DerivedNormalizationProps-16.0.0.txt").read_text(encoding="utf-8").splitlines():
        body = raw.split("#", 1)[0].strip()
        if not body:
            continue
        fields = [item.strip() for item in body.split(";")]
        if fields[1] != name:
            continue
        first, _, last = fields[0].partition("..")
        for cp in range(int(first, 16), (int(last, 16) if last else int(first, 16)) + 1):
            values[cp] = fields[2] if len(fields) > 2 else "Yes"
    return values


def read_exclusions_file():
    """The explicit list, which is a strict subset of Full_Composition_Exclusion."""
    values = set()
    for raw in (DATA / "CompositionExclusions-16.0.0.txt").read_text(encoding="utf-8").splitlines():
        body = raw.split("#", 1)[0].strip()
        if body:
            values.add(int(body.split()[0], 16))
    return values


def parse_zig():
    text = SOURCE.read_text(encoding="utf-8")

    def array(name, base):
        body = re.search(rf"pub const {name} = \[_\]u\d+\{{(.*?)\n\}};", text, re.S).group(1)
        return [int(value, base) for value in re.findall(r"(0x[0-9A-Fa-f]+|\d+),", body)]

    return {
        "combining": array("combining_entries", 16),
        "decomposition": array("decomposition_entries", 16),
        "data": array("decomposition_data", 16),
        "composition": array("composition_index", 10),
        "maybe": array("nfc_qc_maybe", 16),
        "factor": int(re.search(r"pub const expansion_factor: usize = (\d+);", text).group(1)),
        "first_combining": int(re.search(r"pub const first_combining: u21 = (0x[0-9A-Fa-f]+);", text).group(1), 16),
        "first_decomposition": int(re.search(r"pub const first_decomposition: u21 = (0x[0-9A-Fa-f]+);", text).group(1), 16),
        "first_nfc_relevant": int(re.search(r"pub const first_nfc_relevant: u21 = (0x[0-9A-Fa-f]+);", text).group(1), 16),
    }


def check_regeneration(source=SOURCE):
    with tempfile.TemporaryDirectory() as tmp:
        copy = Path(tmp) / "normalization_properties.zig"
        subprocess.run([sys.executable, str(GENERATOR), "--output", str(copy)],
                       check=True, stdout=subprocess.DEVNULL)
        if not filecmp.cmp(copy, source, shallow=False):
            sys.exit("generated normalization tables are stale or regeneration is not deterministic")


def check_stale_source_is_preserved():
    """A failed verification must not repair or overwrite the file it checks."""
    with tempfile.TemporaryDirectory() as tmp:
        stale = Path(tmp) / "stale.zig"
        original = b"// deliberately stale normalization tables\n"
        stale.write_bytes(original)
        try:
            check_regeneration(stale)
        except SystemExit:
            assert stale.read_bytes() == original, "verification overwrote stale source"
        else:
            sys.exit("verification accepted stale source")


def utf8_len(cp):
    return 1 if cp < 0x80 else 2 if cp < 0x800 else 3 if cp < 0x10000 else 4


def hangul_decompose(cp):
    if not S_BASE <= cp < S_BASE + S_COUNT:
        return None
    index = cp - S_BASE
    out = [L_BASE + index // N_COUNT, V_BASE + (index % N_COUNT) // T_COUNT]
    if index % T_COUNT:
        out.append(T_BASE + index % T_COUNT)
    return out


def main():
    check_regeneration()
    check_stale_source_is_preserved()
    ccc, mapping = read_unicode_data()
    full = {cp for cp, value in read_derived("Full_Composition_Exclusion").items() if value == "Yes"}
    nfc_qc = read_derived("NFC_QC")
    nfd_qc = read_derived("NFD_QC")
    table = parse_zig()

    failures = []

    def fail(message):
        failures.append(message)
        if len(failures) <= 20:
            print(message)

    # --- combining classes, over every code point ------------------------
    combining = {entry & 0x3FFFF: entry >> 18 & 0xFF for entry in table["combining"]}
    if len(combining) != len(table["combining"]):
        fail("combining_entries contains a duplicate code point")
    if sorted(combining) != [entry & 0x3FFFF for entry in table["combining"]]:
        fail("combining_entries is not sorted by code point")
    if table["first_combining"] != min(combining):
        fail(f"first_combining is 0x{table['first_combining']:X}, data says 0x{min(combining):X}")
    # The accessors skip their bisection below these thresholds, so a threshold
    # that is too high silently answers "nothing here" for real data.
    lowest_decomposition = min(mapping)
    if table["first_decomposition"] != lowest_decomposition:
        fail(f"first_decomposition is 0x{table['first_decomposition']:X}, data says 0x{lowest_decomposition:X}")
    lowest_maybe = min(cp for cp, value in nfc_qc.items() if value == "M")
    if table["first_nfc_relevant"] != min(lowest_decomposition, lowest_maybe):
        fail(f"first_nfc_relevant is 0x{table['first_nfc_relevant']:X}, data says "
             f"0x{min(lowest_decomposition, lowest_maybe):X}")
    for cp in range(MAXCP):
        if combining.get(cp, 0) != ccc.get(cp, 0):
            fail(f"U+{cp:04X} ccc: table={combining.get(cp, 0)} expected={ccc.get(cp, 0)}")

    # --- decompositions, over every code point ----------------------------
    decomposition = {}
    keys = [entry & 0x3FFFF for entry in table["decomposition"]]
    if keys != sorted(keys):
        fail("decomposition_entries is not sorted by code point")
    for entry in table["decomposition"]:
        cp = entry & 0x3FFFF
        offset = entry >> 18 & 0xFFF
        length = 2 if entry >> 30 & 1 else 1
        decomposition[cp] = (table["data"][offset:offset + length], bool(entry >> 31 & 1))
    for cp in range(MAXCP):
        expected = mapping.get(cp)
        got = decomposition.get(cp)
        if expected is None:
            if got is not None:
                fail(f"U+{cp:04X} has a table decomposition but no canonical mapping")
            continue
        if got is None:
            fail(f"U+{cp:04X} canonical mapping is missing from the table")
            continue
        if got[0] != expected:
            fail(f"U+{cp:04X} decomposition: table={got[0]} expected={expected}")
        if got[1] != (cp in full):
            fail(f"U+{cp:04X} composition_excluded: table={got[1]} expected={cp in full}")
    # Hangul must not appear: the engine handles it arithmetically, and a stray
    # entry would mean two sources of truth.
    for cp in range(S_BASE, S_BASE + S_COUNT):
        if cp in decomposition:
            fail(f"U+{cp:04X} is a Hangul syllable and must not be in the table")

    # --- composition pairs ------------------------------------------------
    expected_pairs = {
        tuple(parts): cp
        for cp, parts in mapping.items()
        if len(parts) == 2 and cp not in full
    }
    got_pairs = {}
    previous = None
    for index in table["composition"]:
        entry = table["decomposition"][index]
        cp = entry & 0x3FFFF
        offset = entry >> 18 & 0xFFF
        if not entry >> 30 & 1:
            fail(f"composition_index points at U+{cp:04X}, which is a singleton")
            continue
        pair = tuple(table["data"][offset:offset + 2])
        if previous is not None and pair <= previous:
            fail(f"composition_index is not strictly ordered at {pair}")
        previous = pair
        if pair in got_pairs:
            fail(f"pair {pair} appears twice in composition_index")
        got_pairs[pair] = cp
    if got_pairs != expected_pairs:
        for pair in set(expected_pairs) - set(got_pairs):
            fail(f"missing composition pair {pair} -> U+{expected_pairs[pair]:04X}")
        for pair in set(got_pairs) - set(expected_pairs):
            fail(f"composition pair {pair} must not be composable")
    for cp in got_pairs.values():
        if cp in full:
            fail(f"U+{cp:04X} is excluded yet reachable by composition")
    explicit = read_exclusions_file()
    if not explicit <= full:
        fail("CompositionExclusions.txt lists a character not in Full_Composition_Exclusion")
    for cp in explicit:
        if cp in got_pairs.values():
            fail(f"U+{cp:04X} is an explicit exclusion yet composable")

    # --- quick check ------------------------------------------------------
    maybe = set(table["maybe"])
    if sorted(maybe) != table["maybe"]:
        fail("nfc_qc_maybe is not sorted")
    for cp in range(MAXCP):
        expected = nfc_qc.get(cp, "Y")
        if expected == "M":
            got = "M"
            if cp not in maybe:
                fail(f"U+{cp:04X} NFC_QC should be Maybe")
                continue
        elif cp in maybe:
            fail(f"U+{cp:04X} NFC_QC is {expected} but is in nfc_qc_maybe")
            continue
        else:
            got = "N" if (cp in decomposition and decomposition[cp][1]) else "Y"
        if got != expected:
            fail(f"U+{cp:04X} NFC_QC: table={got} expected={expected}")
        # NFD_QC is No exactly for the code points that decompose, Hangul
        # included; the table omits Hangul and the engine adds it back.
        expected_nfd = nfd_qc.get(cp, "Y")
        got_nfd = "N" if (cp in decomposition or hangul_decompose(cp) is not None) else "Y"
        if got_nfd != expected_nfd:
            fail(f"U+{cp:04X} NFD_QC: table={got_nfd} expected={expected_nfd}")

    # --- the expansion factor, re-derived ---------------------------------
    def full_decomposition(cp):
        hangul = hangul_decompose(cp)
        if hangul is not None:
            return hangul
        if cp not in mapping:
            return [cp]
        out = []
        for part in mapping[cp]:
            out.extend(full_decomposition(part))
        return out

    worst = 1.0
    longest = 1
    for cp in list(mapping) + [S_BASE, S_BASE + 1]:
        parts = full_decomposition(cp)
        longest = max(longest, len(parts))
        worst = max(worst, sum(utf8_len(part) for part in parts) / utf8_len(cp))
    # Verify that every eligible composition is byte-nonincreasing, making
    # the decomposition bound sufficient for NFC too. Singletons are excluded;
    # algorithmic Hangul compositions shrink six bytes to three.
    for pair, cp in expected_pairs.items():
        if utf8_len(cp) > sum(utf8_len(part) for part in pair):
            fail(f"composition into U+{cp:04X} grows in bytes; revisit the NFC bound")
    if worst > table["factor"]:
        fail(f"expansion_factor {table['factor']} is below the measured {worst:.3f}")
    if longest > 4:
        fail(f"longest recursive decomposition is {longest}, expected at most 4")

    # --- the fixture's worst decomposed run -------------------------------
    # The plan records a maximum of five consecutive non-starters across all
    # five columns; reproduce it so drift is visible rather than silently
    # raising the configured limit.
    longest_run = 0
    cases = 0
    for raw in FIXTURE.read_text(encoding="utf-8").splitlines():
        body = raw.split("#", 1)[0].strip()
        if not body or body.startswith("@"):
            continue
        cases += 1
        for column in body.split(";")[:5]:
            run = 0
            for token in column.split():
                for part in full_decomposition(int(token, 16)):
                    if ccc.get(part, 0):
                        run += 1
                        longest_run = max(longest_run, run)
                    else:
                        run = 0

    if failures:
        sys.exit(f"{len(failures)} mismatches over {MAXCP} code points")
    size = (len(table["combining"]) * 4 + len(table["decomposition"]) * 4 +
            len(table["data"]) * 4 + len(table["composition"]) * 2 + len(table["maybe"]) * 4)
    print(f"ok: {MAXCP} code points verified against the pinned UCD")
    print(f"    {len(table['combining'])} combining classes, {len(table['decomposition'])} decompositions, "
          f"{len(table['composition'])} composition pairs, {len(table['maybe'])} NFC_QC=Maybe")
    print(f"    expansion factor {table['factor']} (measured worst {worst:.3f}), "
          f"longest recursive decomposition {longest}")
    print(f"    fixture: {cases} cases, longest decomposed non-starter run {longest_run}")
    print(f"    {size} bytes of 32768")


if __name__ == "__main__":
    main()
