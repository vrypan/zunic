#!/usr/bin/env python3
"""Fetch Universal Declaration of Human Rights translations as plain text.

    python3 src/tools/fetch-udhr.py            # the default script sample
    python3 src/tools/fetch-udhr.py --all      # every translation in the repo
    python3 src/tools/fetch-udhr.py eng arb    # named ISO 639-3 codes

Writes UTF-8 files to `src/data/udhr/`, which is git-ignored. The corpora are
deliberately **not** checked in: they are third-party text under their own
terms, they change upstream, and the benchmarks that read them are advisory
rather than a correctness gate. Anyone who wants the numbers runs this first.

Why UDHR: the same document in hundreds of languages, so a script comparison
measures the script rather than a difference in subject matter or register.
That is exactly the confound that made zunic's synthesized corpora misleading
for anything sensitive to text *structure* -- see benchmark-udhr.py.

Source note. Unicode hosted "UDHR in Unicode" until January 2024 and now
points at the UN instead, so unicode.org URLs 404. This pulls from the
upstream maintainer's repository, which is where that data went. If it moves
again, only `SOURCE` below needs changing.
"""

import argparse
import re
import sys
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "data" / "udhr"
SOURCE = "https://raw.githubusercontent.com/eric-muller/udhr/main/data/udhr"
NS = "{http://efele.net/udhr}"

# One per script zunic's own corpora cover, plus scripts with properties the
# engines special-case: Thai has no spaces, Hebrew is right-to-left, Greek
# exercises the composed/decomposed accents normalization cares about.
DEFAULT = [
    "eng",  # Latin
    "rus",  # Cyrillic
    "arb",  # Arabic, right-to-left
    "hin",  # Devanagari, combining marks
    "kor",  # Hangul, algorithmic composition
    "jpn",  # Japanese, wide
    "cmn_hans",  # Chinese simplified, wide
    "tha",  # Thai, no word spaces
    "heb",  # Hebrew, right-to-left
    "ell_monotonic",  # Greek, composed accents
]


def plain_text(xml_bytes: bytes) -> str:
    """The document's prose, one line per title or paragraph, in reading order.

    Order matters more than it looks. A benchmark corpus is a sample of how
    text is *arranged*, not just which characters it contains, so collecting
    every title and then every paragraph would hand the engines a block of
    short numbered headings followed by a block of long prose -- a shape no
    real document has, and the exact confound these corpora exist to avoid.

    Only element text is kept; the markup carries no content the benchmarks
    care about, and leaving it in would measure XML rather than the script.
    """
    root = ET.fromstring(xml_bytes)
    wanted = {NS + "title", NS + "para"}
    lines = []
    # A single document-order walk: `iter` yields elements as they appear, so
    # each article's heading stays with the text beneath it.
    for node in root.iter():
        if node.tag not in wanted:
            continue
        text = "".join(node.itertext()).strip()
        if text:
            lines.append(re.sub(r"\s+", " ", text))
    return "\n".join(lines) + "\n"


def fetch(code: str) -> bytes:
    url = f"{SOURCE}/udhr_{code}.xml"
    with urllib.request.urlopen(url, timeout=30) as response:
        return response.read()


def available() -> list[str]:
    """Every translation code the upstream repository publishes."""
    url = "https://api.github.com/repositories/93947749/contents/data/udhr"
    import json

    with urllib.request.urlopen(url, timeout=30) as response:
        entries = json.load(response)
    codes = []
    for entry in entries:
        match = re.fullmatch(r"udhr_(.+)\.xml", entry["name"])
        if match:
            codes.append(match.group(1))
    return sorted(codes)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("codes", nargs="*", help="ISO 639-3 codes; default is a script sample")
    parser.add_argument("--all", action="store_true", help="fetch every available translation")
    parser.add_argument("--list", action="store_true", help="list available codes and exit")
    args = parser.parse_args()

    if args.list:
        print(" ".join(available()))
        return 0

    codes = available() if args.all else (args.codes or DEFAULT)
    OUT.mkdir(parents=True, exist_ok=True)
    written, skipped = 0, []
    for code in codes:
        target = OUT / f"{code}.txt"
        try:
            text = plain_text(fetch(code))
        except (urllib.error.HTTPError, urllib.error.URLError, ET.ParseError) as error:
            skipped.append(f"{code} ({type(error).__name__})")
            continue
        # A stub translation measures nothing; the shortest real ones are
        # several kilobytes.
        if len(text.encode("utf-8")) < 1024:
            skipped.append(f"{code} (too short)")
            continue
        target.write_text(text, encoding="utf-8")
        written += 1

    print(f"wrote {written} file(s) to {OUT.relative_to(ROOT.parent)}")
    if skipped:
        print(f"skipped {len(skipped)}: {', '.join(skipped[:10])}{' ...' if len(skipped) > 10 else ''}")
    return 0 if written else 1


if __name__ == "__main__":
    sys.exit(main())
