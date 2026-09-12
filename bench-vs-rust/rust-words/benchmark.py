#!/usr/bin/env python3
"""Sequential, alternating unicode-segmentation versus Zunic word benchmark.

The same protocol as ../rust-wrap/benchmark.py: build both peers, snapshot the
binaries and corpora into an immutable run directory, then alternate the peers
strictly, swapping which one goes first in each pair.

Exact input bytes and output partitions are verified before and after timing;
timed counts/checksums must match each peer's verified output. Cross-peer
output differences are reported and allowed because Unicode versions differ;
run differential.py to inspect them.
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
from benchmark_contract import parse_timing, parse_dump, check_rows, compare_outputs, compare_operations
from benchmark_report import create_summary, markdown_report, terminal_report as common_terminal_report

ROOT = HERE.parents[1]
CORPUS_DIR = HERE.parent / "texts"
CORPORA = ("arabic", "hindi", "korean", "russian", "source_code", "english", "japanese", "mandarin")
OPS = {
    "zunic": ("zunic_word_bounds", "zunic_word_bounds_collect", "zunic_words"),
    "rust": ("us_word_bounds", "us_word_bounds_collect", "us_words"),
}
PAIRED = (
    ("zunic_word_bounds", "us_word_bounds", "full partition, lazy, with offsets"),
    ("zunic_word_bounds_collect", "us_word_bounds_collect", "the same partition, materialized"),
    ("zunic_words", "us_words", "word-like segments only"),
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


def parse(text: str, peer: str) -> dict[str, dict[str, object]]:
    return parse_timing(text, suite="words", peer=peer, cases=CORPORA, operations=OPS[peer])


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--label", default="unicode-segmentation-zunic-words")
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
    zig_binary = binaries / "zunic-words-bench"
    rust_binary = binaries / "unicode-words-bench"
    shutil.copy2(HERE / "zig-out/bin/zunic-words-bench", zig_binary)
    shutil.copy2(HERE / "target/release/unicode-words-bench", rust_binary)
    for path in corpus_paths:
        shutil.copy2(path, corpus_snapshot / path.name)

    commands = {
        "zunic": [str(zig_binary)],
        "rust": [str(rust_binary), str(corpus_snapshot)],
    }
    checks_before = {peer: run(command + ["--check"], HERE).stdout for peer, command in commands.items()}
    snapshots = {name: (corpus_snapshot / f"{name}.txt").read_bytes() for name in CORPORA}
    outputs = {}
    for peer, command in commands.items():
        dump = run(command + ["--dump"], HERE).stdout
        (output / f"{peer}-before.dump").write_text(dump)
        outputs[peer] = parse_dump(dump, snapshots, "words")
    cross_peer_outputs = compare_outputs(outputs)
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
            pair[peer] = parse(result.stdout, peer)
            check_rows(pair[peer], outputs[peer], "words")
            print(f"completed {peer}-{name}", flush=True)
        pairs.append(pair)
    for peer, command in commands.items():
        dump = run(command + ["--dump"], HERE).stdout
        (output / f"{peer}-after.dump").write_text(dump)
        if parse_dump(dump, snapshots, "words") != outputs[peer]:
            raise RuntimeError(f"{peer}: exact output changed during timing")
    checks_after = {peer: run(command + ["--check"], HERE).stdout for peer, command in commands.items()}
    if checks_before != checks_after:
        raise RuntimeError("segmentation output changed during timing")
    corpus_hashes_after = {name: sha256(path) for name, path in zip(CORPORA, corpus_paths)}
    if corpus_hashes_before != corpus_hashes_after:
        raise RuntimeError("shared corpora changed during timing")

    summary = create_summary(
        suite="words", title="Word boundaries: unicode-segmentation vs Zunic", label=args.label,
        pairs=pairs,
        comparisons=[{"id": z, "label": caption, "zunic": z, "rust": r}
                     for z, r, caption in PAIRED],
        peers={"zunic": {"name": "Zunic", "unicode": "17.0.0"},
               "rust": {"name": "unicode-segmentation 1.13.3", "unicode": "17.0.0"}},
        contract={"input": "bytes", "consumption": "range_checksum_v1"},
        outputs=cross_peer_outputs,
        operation_outputs=compare_operations(outputs, "words", [
            {"id": z, "zunic": z, "rust": r} for z, r, _ in PAIRED], CORPORA),
        notes=["UTF-8 validation/decoding and the range checksum are timed; file I/O is excluded."],
        environment={"platform": platform.platform(), "machine": platform.machine(), "python": sys.version,
                     "zig": subprocess.check_output(["zig", "version"], text=True).strip(),
                     "rustc": subprocess.check_output(["rustc", "--version"], text=True).strip(),
                     "rustflags": env["RUSTFLAGS"]},
        provenance={"binary_hashes": {"zunic": sha256(zig_binary), "rust": sha256(rust_binary)},
                    "corpus_hashes_before": corpus_hashes_before, "corpus_hashes_after": corpus_hashes_after,
                    "checks": checks_before},
    )
    (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    markdown = markdown_report(summary)
    (output / "comparison.md").write_text(markdown)
    print(common_terminal_report(summary))
    print(f"Saved {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
