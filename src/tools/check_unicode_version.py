"""Shared check: the version zunic publishes must match the vendored data.

Imported by each generator's verifier. A Unicode upgrade replaces the files in
src/data, so comparing the public constant against their names catches a stale
`unicode_version` no matter which table is regenerated first.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def check(*data_files):
    """Compare root.zig's unicode_version against the given data filenames."""
    text = (ROOT / "root.zig").read_text(encoding="utf-8")
    match = re.search(
        r"pub const unicode_version: std\.SemanticVersion = "
        r"\.\{ \.major = (\d+), \.minor = (\d+), \.patch = (\d+) \};",
        text,
    )
    if not match:
        sys.exit("root.zig has no parsable unicode_version")
    published = ".".join(match.groups())

    versions = set()
    for name in data_files:
        found = re.search(r"-(\d+\.\d+\.\d+)\.txt$", name)
        if not found:
            sys.exit(f"cannot read a Unicode version from {name}")
        versions.add(found.group(1))
    if len(versions) != 1:
        sys.exit(f"vendored data mixes Unicode versions: {sorted(versions)}")
    pinned = versions.pop()
    if published != pinned:
        sys.exit(f"root.zig publishes Unicode {published}; the pinned data is {pinned}")
    return pinned
