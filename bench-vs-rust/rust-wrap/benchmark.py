#!/usr/bin/env python3
"""Sequential, alternating Rust wrapping versus Zunic benchmark."""
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
    "zunic": ("zunic_iterate", "zunic_collect", "zunic_first24"),
    "rust": (
        "textwrap_first_fit",
        "textwrap_first_fit_take24",
    ),
}
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
    return parse_timing(text, suite="wrap", peer=peer, cases=CORPORA, operations=OPS[peer])


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--label", default="textwrap-zunic")
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
    zig_binary = binaries / "zunic-wrap-bench"
    rust_binary = binaries / "cellwidth-wrap-bench"
    shutil.copy2(HERE / "zig-out/bin/zunic-wrap-bench", zig_binary)
    shutil.copy2(HERE / "target/release/cellwidth-wrap-bench", rust_binary)
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
        outputs[peer] = parse_dump(dump, snapshots, "wrap")
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
            check_rows(pair[peer], outputs[peer], "wrap")
            print(f"completed {peer}-{name}", flush=True)
        pairs.append(pair)
    for peer, command in commands.items():
        dump = run(command + ["--dump"], HERE).stdout
        (output / f"{peer}-after.dump").write_text(dump)
        if parse_dump(dump, snapshots, "wrap") != outputs[peer]:
            raise RuntimeError(f"{peer}: exact output changed during timing")
    checks_after = {peer: run(command + ["--check"], HERE).stdout for peer, command in commands.items()}
    if checks_before != checks_after:
        raise RuntimeError("wrapper output changed during timing")
    corpus_hashes_after = {name: sha256(path) for name, path in zip(CORPORA, corpus_paths)}
    if corpus_hashes_before != corpus_hashes_after:
        raise RuntimeError("shared corpora changed during timing")

    comparisons = [
        {"id": "full_iterate", "label": "Full document: iterator vs textwrap", "zunic": "zunic_iterate", "rust": "textwrap_first_fit"},
        {"id": "full_collect", "label": "Full document: collected results", "zunic": "zunic_collect", "rust": "textwrap_first_fit"},
        {"id": "first24", "label": "First 24 lines", "zunic": "zunic_first24", "rust": "textwrap_first_fit_take24"},
    ]
    summary = create_summary(
        suite="wrap", title="Wrapping: textwrap vs Zunic", label=args.label, pairs=pairs,
        comparisons=comparisons,
        peers={"zunic": {"name": "Zunic", "unicode": "17.0.0"},
               "rust": {"name": "textwrap 0.16.2", "unicode": "linebreak 15.0.0; width 17.0.0"}},
        contract={"input": "bytes", "consumption": "line_bytes_fnv1"}, outputs=cross_peer_outputs,
        operation_outputs=compare_operations(outputs, "wrap", comparisons, CORPORA),
        notes=["Version and wrapping-policy discrepancies are accepted and reported.",
               "UTF-8 validation/decoding and line-byte checksums are timed; file I/O is excluded."],
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
