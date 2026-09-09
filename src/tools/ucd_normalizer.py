#!/usr/bin/env python3
"""Canonical NFD and NFC derived from the pinned UCD.

A verification oracle, not a port of the Zig engine: it is written from the
UAX #15 rules against the vendored data files, so an implementation checked
against it is checked against a second opinion rather than against itself.

`validate` proves the oracle before anything trusts it, by reproducing every
case in the official `NormalizationTest` fixture. Call it first.

Kept separate from any one verifier so more than one can use it, and so the
normalizer can be read and reviewed on its own.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
NORMALIZATION_TEST = DATA / "NormalizationTest-16.0.0.txt"

S_BASE, L_BASE, V_BASE, T_BASE = 0xAC00, 0x1100, 0x1161, 0x11A7
L_COUNT, V_COUNT, T_COUNT = 19, 21, 28
N_COUNT = V_COUNT * T_COUNT
S_COUNT = L_COUNT * N_COUNT


def read_canonical_mappings():
    """Canonical decompositions only -- the tagged ones are compatibility."""
    canonical = {}
    for raw in (DATA / "UnicodeData-16.0.0.txt").read_text(encoding="utf-8").splitlines():
        parts = raw.split(";")
        text = parts[5].strip()
        if text and not text.startswith("<"):
            canonical[int(parts[0], 16)] = [int(item, 16) for item in text.split()]
    return canonical


def read_full_composition_exclusion():
    """The derived property NFC uses to refuse to rebuild a character."""
    excluded = set()
    for raw in (DATA / "DerivedNormalizationProps-16.0.0.txt").read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        parts = [part.strip() for part in line.split(";")]
        if len(parts) < 2 or parts[1] != "Full_Composition_Exclusion":
            continue
        first, _, last = parts[0].partition("..")
        for cp in range(int(first, 16), int(last or first, 16) + 1):
            excluded.add(cp)
    return excluded


class Normalizer:
    """Canonical NFD and NFC, derived from the pinned UCD.

    Written here rather than taken from `unicodedata` so the oracle is pinned
    to the same Unicode release as the tables, and validated against the
    official NormalizationTest fixture before it is trusted.
    """

    def __init__(self, ccc, canonical, excluded):
        self.ccc = ccc
        self.canonical = canonical
        self.pairs = {}
        for cp, seq in canonical.items():
            # A primary composite: a two-character canonical decomposition
            # whose target NFC is allowed to rebuild.
            if len(seq) == 2 and cp not in excluded:
                self.pairs[(seq[0], seq[1])] = cp
        self._nfd_cache = {}

    def klass(self, cp):
        return self.ccc.get(cp, 0)

    def decompose(self, cp):
        if cp in self._nfd_cache:
            return self._nfd_cache[cp]
        if S_BASE <= cp < S_BASE + S_COUNT:
            index = cp - S_BASE
            out = [L_BASE + index // N_COUNT, V_BASE + (index % N_COUNT) // T_COUNT]
            if index % T_COUNT:
                out.append(T_BASE + index % T_COUNT)
        elif cp in self.canonical:
            out = []
            for part in self.canonical[cp]:
                out.extend(self.decompose(part))
        else:
            out = [cp]
        self._nfd_cache[cp] = out
        return out

    def order(self, seq):
        """Canonical ordering: a stable sort of each non-starter run."""
        out = list(seq)
        i = 0
        while i < len(out):
            if self.klass(out[i]) == 0:
                i += 1
                continue
            j = i
            while j < len(out) and self.klass(out[j]) != 0:
                j += 1
            out[i:j] = sorted(out[i:j], key=self.klass)
            i = j
        return out

    def nfd(self, seq):
        expanded = []
        for cp in seq:
            expanded.extend(self.decompose(cp))
        return self.order(expanded)

    def compose_pair(self, first, second):
        if L_BASE <= first < L_BASE + L_COUNT and V_BASE <= second < V_BASE + V_COUNT:
            return S_BASE + ((first - L_BASE) * V_COUNT + (second - V_BASE)) * T_COUNT
        if (S_BASE <= first < S_BASE + S_COUNT and (first - S_BASE) % T_COUNT == 0
                and T_BASE < second < T_BASE + T_COUNT):
            return first + (second - T_BASE)
        return self.pairs.get((first, second))

    def nfc(self, seq):
        decomposed = self.nfd(seq)
        if not decomposed:
            return []
        out = [decomposed[0]]
        starter = 0 if self.klass(decomposed[0]) == 0 else None
        # -1 means nothing has been retained since the starter, so the next
        # character sits against it and cannot be blocked.
        last_ccc = -1 if self.klass(decomposed[0]) == 0 else self.klass(decomposed[0])
        for cp in decomposed[1:]:
            current = self.klass(cp)
            if starter is not None and last_ccc < current:
                composed = self.compose_pair(out[starter], cp)
                if composed is not None:
                    out[starter] = composed
                    continue
            if current == 0:
                starter = len(out)
                last_ccc = -1
            else:
                last_ccc = current
            out.append(cp)
        return out


def validate(normalizer):
    """Check the oracle's NFD and NFC against the official conformance file.

    Only then is it fit to produce expected stream-safe output.
    """
    def parse(field):
        return [int(token, 16) for token in field.split()]

    cases = 0
    for raw in NORMALIZATION_TEST.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line or line.startswith("@"):
            continue
        columns = [part.strip() for part in line.split(";") if part.strip()]
        source, nfc, nfd = parse(columns[0]), parse(columns[1]), parse(columns[2])
        for start in (source, nfc, nfd):
            if normalizer.nfd(start) != nfd:
                sys.exit(f"oracle NFD disagrees with NormalizationTest on {columns[0]}")
            if normalizer.nfc(start) != nfc:
                sys.exit(f"oracle NFC disagrees with NormalizationTest on {columns[0]}")
        cases += 1
    return cases


