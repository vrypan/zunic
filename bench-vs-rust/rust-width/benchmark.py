#!/usr/bin/env python3
"""Sequential, alternating unicode-width versus Zunic display-width benchmark.

The same protocol as ../rust-words/benchmark.py: build both peers, snapshot
the binaries and corpora into an immutable run directory, then alternate the
peers strictly, swapping which one goes first in each pair.

Width is a single scalar per corpus rather than a list of ranges, so this
verifies dumps directly (like ../rust-normalize/benchmark.py) instead of going
through the shared range-record contract in benchmark_contract.py. Zunic
measures grapheme clusters; unicode-width measures individual chars, so the
two peers are expected to disagree on any corpus with combining marks or
multi-scalar clusters. That disagreement is reported, not hidden.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
import uuid
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from benchmark_contract import fields, parse_timing
from benchmark_report import create_summary, markdown_report, terminal_report as common_terminal_report

ROOT = HERE.parents[1]
CORPUS_DIR = HERE.parent / "texts"
CORPORA = ("arabic", "hindi", "korean", "russian", "source_code", "english", "japanese", "mandarin")
OPS = {
    "zunic": ("zunic_width",),
    "rust": ("unicode_width_str",),
}
PAIRED = (
    ("zunic_width", "unicode_width_str", "whole-text width"),
)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command: list[str], cwd: Path, *, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True)
    if result.returncode:
        sys.stderr.write(result.stdout)
        sys.stderr.write(result.stderr)
        result.check_returncode()
    return result


def check_dump(text: str, snapshots: dict[str, bytes]) -> dict[str, int]:
    outputs: dict[str, int] = {}
    for line in text.splitlines():
        row = fields(line)
        if "case" not in row or "input" not in row or "width" not in row:
            continue
        case = row["case"]
        if case not in snapshots or case in outputs:
            raise ValueError(f"unexpected or duplicate corpus: {case}")
        if bytes.fromhex(row["input"]) != snapshots[case]:
            raise ValueError(f"{case}: binary input differs from corpus snapshot")
        outputs[case] = int(row["width"])
    if outputs.keys() != set(snapshots):
        raise ValueError("incomplete dump")
    return outputs


def parse(text: str, peer: str, outputs: dict[str, int], snapshots: dict[str, bytes]) -> dict[str, dict[str, object]]:
    nested = parse_timing(text, suite="width", peer=peer, cases=CORPORA, operations=OPS[peer])
    for case in CORPORA:
        for operation in OPS[peer]:
            row = nested[case][operation]
            if (row["checksum"] != outputs[case] or row["units"] != outputs[case] or
                    row["bytes"] != len(snapshots[case])):
                raise ValueError(f"{peer}/{case}/{operation}: timed result differs from verified output")
    return nested


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--label", default="unicode-width-zunic")
    parser.add_argument("--pairs", type=int, choices=(1, 3), default=3)
    parser.add_argument("--skip-build", action="store_true")
    args = parser.parse_args()

    corpus_paths = [CORPUS_DIR / f"{name}.txt" for name in CORPORA]
    corpus_hashes_before = {name: sha256(path) for name, path in zip(CORPORA, corpus_paths)}
    env = dict(os.environ, RUSTFLAGS="-C target-cpu=native")
    zig_env = dict(os.environ, ZIG_GLOBAL_CACHE_DIR=str(HERE / ".zig-global-cache"))
    if not args.skip_build:
        run(["zig", "build", "-Doptimize=ReleaseFast", "-Dcpu=native", "--summary", "all"], HERE, env=zig_env)
        run(["cargo", "build", "--locked", "--release"], HERE, env=env)

    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    output = ROOT / "bench-vs-rust" / "benchmarks" / f"{stamp}-{args.label}-{uuid.uuid4().hex[:6]}"
    binaries = output / "bin"
    corpus_snapshot = output / "texts"
    binaries.mkdir(parents=True)
    corpus_snapshot.mkdir()
    zig_binary = binaries / "zunic-width-bench"
    rust_binary = binaries / "unicode-width-bench"
    shutil.copy2(HERE / "zig-out/bin/zunic-width-bench", zig_binary)
    shutil.copy2(HERE / "target/release/unicode-width-bench", rust_binary)
    for path in corpus_paths:
        shutil.copy2(path, corpus_snapshot / path.name)

    commands = {
        "zunic": [str(zig_binary)],
        "rust": [str(rust_binary), str(corpus_snapshot)],
    }
    snapshots = {name: (corpus_snapshot / f"{name}.txt").read_bytes() for name in CORPORA}
    outputs = {}
    for peer, command in commands.items():
        dump = run(command + ["--dump"], HERE).stdout
        (output / f"{peer}-before.dump").write_text(dump)
        outputs[peer] = check_dump(dump, snapshots)
    cross_peer_outputs = {case: {"equal": outputs["zunic"][case] == outputs["rust"][case],
                                  "zunic_count": outputs["zunic"][case], "rust_count": outputs["rust"][case]}
                           for case in CORPORA}

    pairs = []
    for index in range(args.pairs):
        name = chr(ord("a") + index)
        order = ("zunic", "rust") if index % 2 == 0 else ("rust", "zunic")
        pair: dict[str, object] = {"name": name, "order": list(order)}
        for peer in order:
            print(f"starting {peer}-{name}", flush=True)
            result = run(commands[peer] + ["--bench"], HERE)
            (output / f"{peer}-{name}.stdout.txt").write_text(result.stdout)
            (output / f"{peer}-{name}.stderr.txt").write_text(result.stderr)
            pair[peer] = parse(result.stdout, peer, outputs[peer], snapshots)
            print(f"completed {peer}-{name}", flush=True)
        pairs.append(pair)
    for peer, command in commands.items():
        dump = run(command + ["--dump"], HERE).stdout
        (output / f"{peer}-after.dump").write_text(dump)
        if check_dump(dump, snapshots) != outputs[peer]:
            raise RuntimeError(f"{peer}: exact output changed during timing")
    corpus_hashes_after = {name: sha256(path) for name, path in zip(CORPORA, corpus_paths)}
    if corpus_hashes_before != corpus_hashes_after:
        raise RuntimeError("shared corpora changed during timing")

    summary = create_summary(
        suite="width", title="Display width: unicode-width vs Zunic", label=args.label,
        pairs=pairs,
        comparisons=[{"id": z, "label": caption, "zunic": z, "rust": r}
                     for z, r, caption in PAIRED],
        peers={"zunic": {"name": "Zunic", "unicode": "17.0.0"},
               "rust": {"name": "unicode-width 0.2.2", "unicode": "17.0.0"}},
        contract={"input": "bytes", "consumption": "width_sum_v1"},
        outputs=cross_peer_outputs,
        operation_outputs={z: dict(cross_peer_outputs) for z, _, _ in PAIRED},
        notes=["Zunic measures grapheme clusters; unicode-width measures individual chars, "
               "so corpora with combining marks or joining behavior are expected to differ.",
               "unicode-width counts newline and tab as one column each; Zunic's width policy "
               "drops control characters, so ASCII-heavy corpora differ by their control-byte count.",
               "UTF-8 validation/decoding is timed; file I/O is excluded."],
        environment={"platform": platform.platform(), "machine": platform.machine(), "python": sys.version,
                     "zig": subprocess.check_output(["zig", "version"], text=True).strip(),
                     "rustc": subprocess.check_output(["rustc", "--version"], text=True).strip(),
                     "rustflags": env["RUSTFLAGS"]},
        provenance={"binary_hashes": {"zunic": sha256(zig_binary), "rust": sha256(rust_binary)},
                    "corpus_hashes_before": corpus_hashes_before, "corpus_hashes_after": corpus_hashes_after},
    )
    (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    markdown = markdown_report(summary)
    (output / "comparison.md").write_text(markdown)
    print(common_terminal_report(summary))
    print(f"Saved {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
