"""Prepare pinned reference texts as part of make build."""
from __future__ import annotations

import hashlib
import json
import subprocess
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent


def prepare(destination: Path = HERE / "texts") -> None:
    manifest = json.loads((HERE / "corpus.lock.json").read_text())
    base = (f"https://raw.githubusercontent.com/{manifest['repository']}/"
            f"{manifest['revision']}/{manifest['directory']}")
    destination.mkdir(parents=True, exist_ok=True)
    for name, expected in manifest["files"].items():
        target = destination / name
        if target.exists():
            if hashlib.sha256(target.read_bytes()).hexdigest() != expected:
                raise ValueError(f"{target}: corpus checksum mismatch; move it aside and rebuild")
            continue
        print(f"Fetching corpus file {name}", flush=True)
        with tempfile.NamedTemporaryFile(dir=destination, prefix=f".{name}.", delete=False) as output:
            temporary = Path(output.name)
        try:
            subprocess.run(["curl", "--fail", "--location", "--silent", "--show-error",
                            "--retry", "3", "--max-time", "60", f"{base}/{name}",
                            "--output", str(temporary)], check=True)
            if hashlib.sha256(temporary.read_bytes()).hexdigest() != expected:
                raise ValueError(f"{name}: downloaded corpus checksum mismatch")
            temporary.replace(target)
        finally:
            temporary.unlink(missing_ok=True)


if __name__ == "__main__":
    prepare()
