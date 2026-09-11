#!/usr/bin/env python3
"""Exhaustively verify the generated stream-safe counts, and act as the
independent oracle for stream-safe normalization.

Run from the repository root:
    python3 src/tools/test-stream-safe-properties.py
    python3 src/tools/test-stream-safe-properties.py --write-fixture

Independent by construction: it re-derives the NFKD form of every code point
from the pinned UCD and decodes src/stream_safe_properties.zig by parsing the
emitted Zig, sharing no code with the generator. It also re-runs the generator
into a temporary location and compares bytes.

Beyond the counts it checks two further things:

  * The safety invariant the fixed 32-entry stream-safe buffer rests on. The
    engine counts non-starters over the *canonical* decomposition while
    insertion is driven by *compatibility* counts, so a scalar whose NFKD
    holds a starter but whose NFD does not would let a run outgrow the
    budget. This asserts no such scalar exists, over every code point.

  * `src/data/stream-safe-fixture.txt`, the expected output of
    `normalizeStreamSafe` for cases that stress insertion. Those expectations
    come from a canonical normalizer written here and validated against the
    official NormalizationTest fixture, plus an insertion pass written from
    the UAX #15 section 13 rules using UCD-derived counts. Nothing in that
    chain touches zunic's implementation, so the Zig test that reads the
    fixture is checked against a genuinely separate answer rather than
    against a second copy of its own algorithm.
"""

import argparse
import re
import subprocess
import sys
import tempfile
from pathlib import Path

from check_unicode_version import check as check_unicode_version
from ucd_normalizer import Normalizer, read_canonical_mappings, read_full_composition_exclusion
from ucd_normalizer import validate as validate_normalizer

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
SOURCE = ROOT / "tables/stream_safe_properties.zig"
GENERATOR = ROOT / "tools" / "generate-stream-safe-properties.py"
FIXTURE = DATA / "stream-safe-fixture.txt"
MAXCP = 0x110000
CGJ = 0x034F

S_BASE, L_BASE, V_BASE, T_BASE = 0xAC00, 0x1100, 0x1161, 0x11A7
L_COUNT, V_COUNT, T_COUNT = 19, 21, 28
N_COUNT = V_COUNT * T_COUNT
S_COUNT = L_COUNT * N_COUNT


def read_unicode_data():
    ccc, mapping = {}, {}
    for raw in (DATA / "UnicodeData-17.0.0.txt").read_text(encoding="utf-8").splitlines():
        parts = raw.split(";")
        cp = int(parts[0], 16)
        if int(parts[3]):
            ccc[cp] = int(parts[3])
        text = parts[5].strip()
        if text:
            items = text.split()
            # Keep compatibility mappings; only the <tag> is dropped.
            if items[0].startswith("<"):
                items = items[1:]
            mapping[cp] = [int(item, 16) for item in items]
    return ccc, mapping


def parse_zig():
    text = SOURCE.read_text(encoding="utf-8")

    def array(name):
        body = re.search(rf"pub const {name} = \[_\]u8\{{(.*?)\n?\}};", text, re.S).group(1)
        return [int(v, 16) if v.startswith("0x") else int(v) for v in re.findall(r"(0x[0-9A-Fa-f]+|\d+),", body)]

    return {
        "class_table": array("class_table"),
        "stage1": array("class_stage1"),
        "stage2": array("class_stage2"),
        "stage3": array("class_stage3"),
        "limit": int(re.search(r"pub const class_limit: u21 = (0x[0-9A-Fa-f]+);", text).group(1), 16),
        "above": int(re.search(r"pub const class_above_limit: u8 = (\d+);", text).group(1)),
        "s1": int(re.search(r"const class_s1 = (\d+);", text).group(1)),
        "s2": int(re.search(r"const class_s2 = (\d+);", text).group(1)),
        "stream_safe_limit": int(re.search(r"pub const stream_safe_limit: usize = (\d+);", text).group(1)),
        "cgj": int(re.search(r"pub const combining_grapheme_joiner: u21 = (0x[0-9A-Fa-f]+);", text).group(1), 16),
    }


def stream_safe(seq, counts_for, limit):
    """UAX #15 section 13 insertion, over original scalars.

    Written from the rule rather than from zunic: a CGJ goes in front of the
    scalar that would push the running non-starter count past `limit`. A run
    of exactly `limit` is allowed and left alone.
    """
    out = []
    count = 0
    for cp in seq:
        leading, trailing, has_starter = counts_for(cp)
        # A decomposition holding a starter breaks the run and leaves only
        # its own trailing non-starters behind; one without extends it.
        extended = trailing if has_starter else count + leading
        if extended > limit:
            out.append(CGJ)
            count = trailing
        else:
            count = extended
        out.append(cp)
    return out


def build_cases(limit, divergent):
    """Inputs that stress insertion, as (description, scalars) pairs."""
    mark = 0x0305          # combining overline: never composes with "a"
    other = 0x0316         # a different combining class, to force reordering
    cases = []

    def case(name, scalars):
        cases.append((name, scalars))

    case("empty", [])
    case("ascii only", list(b"hello"))
    case("composed accents, no insertion", [0x0043, 0x0061, 0x0066, 0x00E9])
    case("decomposed accents, no insertion", [0x0043, 0x0061, 0x0066, 0x0065, 0x0301])

    # The boundary the standard draws: `limit` is allowed, `limit + 1` is not.
    for count in (limit - 1, limit, limit + 1, limit + 2, 2 * limit,
                  2 * limit + 1, 3 * limit + 5):
        case(f"{count} marks after a starter", [0x0061] + [mark] * count)
        case(f"{count} leading marks, no starter", [mark] * count)

    # Mixed classes, so canonical ordering has to run inside a long run.
    case("mixed-class long run", [0x0061] + [mark, other] * (limit // 2 + 3))

    # Several runs separated by starters: each starter resets the count.
    case("runs separated by starters",
         ([0x0061] + [mark] * (limit - 1)) * 4)
    case("runs at exactly the limit, separated",
         ([0x0061] + [mark] * limit) * 3)

    # A CGJ already in the input is an ordinary starter and must survive.
    case("existing CGJ inside a run", [0x0061] + [mark] * 5 + [CGJ] + [mark] * 5)
    case("existing CGJ before a long run", [0x0061, CGJ] + [mark] * (limit + 1))

    # Precomposed characters whose marks only appear after decomposition.
    case("precomposed characters with hidden marks", [0x1E69] * 20)
    case("hidden marks pushed past the limit", [0x0061] + [0x1E69] * (limit + 2))
    case("hangul", [0xAC00, 0xD4DB, 0x1100, 0x1161, 0x11A8])

    # Scalars whose canonical and compatibility counts differ: insertion is
    # driven by the compatibility count, so these are the cases where a
    # canonical-only counter would insert in the wrong place.
    for cp in divergent[:4]:
        case(f"U+{cp:04X}, canonical and compatibility counts differ",
             [0x0061] + [cp] * 12)
        case(f"U+{cp:04X} filling a run", [0x0061] + [cp] * (limit + 1))

    return cases


def format_scalars(scalars):
    return " ".join(f"{cp:04X}" for cp in scalars)


def build_fixture(normalizer, counts_for, limit, divergent):
    lines = [
        "# Expected output of zunic's normalizeStreamSafe, for Unicode 17.0.0.",
        "# Generated by src/tools/test-stream-safe-properties.py --write-fixture;",
        "# do not hand-edit. Each line is:",
        "#",
        "#   source ; stream-safe NFD ; stream-safe NFC ; description",
        "#",
        "# Columns are space-separated hex code points. The two output columns",
        "# are UAX #15 section 13 insertion applied to the source scalars,",
        "# then canonical normalization -- in that order.",
        "",
    ]
    for name, scalars in build_cases(limit, divergent):
        inserted = stream_safe(scalars, counts_for, limit)
        lines.append("; ".join((
            format_scalars(scalars),
            format_scalars(normalizer.nfd(inserted)),
            format_scalars(normalizer.nfc(inserted)),
            name,
        )))
    return "\n".join(lines) + "\n"


def check_regeneration():
    with tempfile.TemporaryDirectory() as tmp:
        copy = Path(tmp) / "stream_safe_properties.zig"
        subprocess.run([sys.executable, str(GENERATOR), "--output", str(copy)],
                       check=True, stdout=subprocess.DEVNULL)
        if copy.read_bytes() != SOURCE.read_bytes():
            sys.exit("generated stream-safe tables are stale or regeneration is not deterministic")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write-fixture", action="store_true",
                        help="regenerate src/data/stream-safe-fixture.txt from the oracle")
    args = parser.parse_args()

    check_unicode_version("UnicodeData-17.0.0.txt")
    check_regeneration()
    ccc, mapping = read_unicode_data()
    table = parse_zig()

    if table["stream_safe_limit"] != 30:
        sys.exit(f"stream_safe_limit is {table['stream_safe_limit']}; UAX #15 section 13 says 30")
    if table["cgj"] != 0x034F:
        sys.exit(f"combining_grapheme_joiner is U+{table['cgj']:04X}; expected U+034F")

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

    s1, s2 = table["s1"], table["s2"]
    mid_bits = s1 - s2

    def counts_of(cp):
        if cp < 128:
            return 0, 0, True
        if cp >= table["limit"]:
            packed = table["class_table"][table["above"]]
        else:
            mid = table["stage1"][cp >> s1]
            leaf = table["stage2"][(mid << mid_bits) | (cp >> s2 & ((1 << mid_bits) - 1))]
            packed = table["class_table"][table["stage3"][(leaf << s2) | (cp & ((1 << s2) - 1))]]
        return packed & 7, packed >> 3 & 7, bool(packed >> 6 & 1)

    normalizer = Normalizer(ccc, read_canonical_mappings(), read_full_composition_exclusion())

    def edges(parts):
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

    failures = 0
    worst_run = 0
    unsafe = 0
    divergent = []
    for cp in range(MAXCP):
        parts = nfkd(cp)
        want = edges(parts)
        got = counts_of(cp)
        if got != want:
            failures += 1
            if failures <= 20:
                print(f"U+{cp:04X}: table={got} expected={want}")
        run = 0
        for part in parts:
            run = run + 1 if ccc.get(part, 0) else 0
            worst_run = max(worst_run, run)

        # The invariant the fixed stream-safe buffer depends on. Insertion is
        # budgeted with compatibility counts, but the engine accumulates the
        # *canonical* decomposition, so the canonical side must never see a
        # longer run than the budget allows: it must not keep accumulating
        # where the budget resets, and its edge counts must not be larger.
        canonical_parts = normalizer.decompose(cp)
        canonical_leading, canonical_trailing, canonical_has_starter = edges(canonical_parts)
        compat_leading, compat_trailing, compat_has_starter = want
        if ((compat_has_starter and not canonical_has_starter)
                or canonical_leading > compat_leading
                or canonical_trailing > compat_trailing):
            unsafe += 1
            if unsafe <= 10:
                print(f"U+{cp:04X}: canonical run can outgrow the stream-safe budget "
                      f"(canonical={canonical_leading, canonical_trailing, canonical_has_starter} "
                      f"compatibility={want})")
        if (canonical_leading, canonical_trailing, canonical_has_starter) != want:
            # Sort the discriminating ones first. A scalar whose NFKD holds no
            # starter extends the run under compatibility counting while its
            # canonical form resets it -- U+FF9E and U+FF9F are the only two,
            # and they are the cases a canonical-only counter would get wrong.
            divergent.append((0 if not compat_has_starter else 1, cp))

    if unsafe:
        failures += unsafe
        print(f"{unsafe} scalars break the canonical-vs-compatibility run invariant")

    # Insertion only ever happens before a scalar, so a scalar whose own NFKD
    # holds more than the limit could not be made stream safe at all.
    if worst_run > table["stream_safe_limit"]:
        failures += 1
        print(f"a single scalar's NFKD has {worst_run} consecutive non-starters, over the limit")

    if failures:
        sys.exit(f"{failures} mismatches over {MAXCP} code points")

    # The oracle is only worth trusting once it reproduces the official
    # conformance data, so validate it before generating any expectations.
    conformance_cases = validate_normalizer(normalizer)

    limit = table["stream_safe_limit"]

    def counts_from_ucd(cp):
        return edges(nfkd(cp))

    ordered_divergent = [cp for _, cp in sorted(divergent)]
    fixture_cases = build_cases(limit, ordered_divergent)
    fixture = build_fixture(normalizer, counts_from_ucd, limit, ordered_divergent)
    if args.write_fixture:
        FIXTURE.write_text(fixture, encoding="utf-8")
        print(f"wrote {FIXTURE.relative_to(ROOT.parent)}")
    elif not FIXTURE.exists():
        sys.exit(f"{FIXTURE} is missing; run with --write-fixture")
    elif FIXTURE.read_text(encoding="utf-8") != fixture:
        sys.exit(f"{FIXTURE} is stale; run with --write-fixture")

    size = len(table["class_table"]) + len(table["stage1"]) + len(table["stage2"]) + len(table["stage3"])
    print(f"ok: {MAXCP} code points verified against the pinned UCD")
    print(f"    {len(table['class_table'])} classes, {size} bytes")
    print(f"    worst NFKD non-starter run in one scalar: {worst_run} (limit {limit})")
    print(f"    canonical runs never outgrow the compatibility budget "
          f"({len(divergent)} scalars where the two counts differ)")
    print(f"    oracle agrees with NormalizationTest on {conformance_cases} cases")
    print(f"    fixture: {len(fixture_cases)} cases, "
          f"{sum(1 for _, scalars in fixture_cases if scalars)} non-empty")


if __name__ == "__main__":
    main()
