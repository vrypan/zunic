#!/usr/bin/env python3
"""ANSI stripping, using the common sequential comparison protocol."""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import platform
import re
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
CORPUS_DIR = HERE / "texts"
from cases import CORPORA, DIAGNOSTICS
OPS = {"zunic": ("zunic_reuse", "zunic_alloc"), "rust": ("rust_reuse", "rust_alloc")}
PAIRED = (
    ("zunic_reuse", "rust_reuse", "Reused output: stripAnsi vs Writer"),
    ("zunic_alloc", "rust_alloc", "Allocated output: stripAnsi + allocation vs strip"),
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
    return parse_timing(text, suite="strip_ansi", peer=peer, cases=CORPORA, operations=OPS[peer])


def source_hashes():
    paths = list((ROOT / "src").rglob("*.zig"))
    paths += [ROOT / "build.zig", ROOT / "build.zig.zon"]
    paths += [HERE / name for name in ("zunic-strip-ansi.zig", "src/main.rs", "build.zig",
              "build.zig.zon", "Cargo.toml", "Cargo.lock", "benchmark.py", "cases.py")]
    paths += [HERE.parent / name for name in ("benchmark_contract.py", "benchmark_report.py", "benchmark_table.py")]
    return {str(path.relative_to(ROOT)): sha256(path) for path in sorted(paths)}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--label", default="strip-ansi")
    parser.add_argument("--pairs", type=int, choices=(1, 3), default=3)
    parser.add_argument("--skip-build", action="store_true")
    args = parser.parse_args()

    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}", args.label):
        parser.error("invalid label")
    corpus_paths = [CORPUS_DIR / f"{name}.txt" for name in CORPORA + DIAGNOSTICS]
    corpus_hashes_before = {name: sha256(path) for name, path in zip(CORPORA + DIAGNOSTICS, corpus_paths)}
    sources_before = source_hashes()
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
    zig_binary = binaries / "zunic-strip-ansi-bench"
    rust_binary = binaries / "rust-strip-ansi-bench"
    shutil.copy2(HERE / "zig-out/bin/zunic-strip-ansi-bench", zig_binary)
    shutil.copy2(HERE / "target/release/rust-strip-ansi-bench", rust_binary)
    for path in corpus_paths:
        shutil.copy2(path, corpus_snapshot / path.name)

    commands = {
        "zunic": [str(zig_binary)],
        "rust": [str(rust_binary), str(corpus_snapshot)],
    }
    checks_before = {peer: run(command + ["--check"], HERE).stdout for peer, command in commands.items()}
    snapshots = {name: (corpus_snapshot / f"{name}.txt").read_bytes() for name in CORPORA + DIAGNOSTICS}
    outputs = {}
    for peer, command in commands.items():
        dump = run(command + ["--dump"], HERE).stdout
        (output / f"{peer}-before.dump").write_text(dump)
        outputs[peer] = parse_dump(dump, snapshots, "strip_ansi")
    cross_peer_outputs = compare_outputs(outputs)
    if any(not cross_peer_outputs[name]["equal"] for name in CORPORA):
        raise RuntimeError("timed corpora must produce identical bytes; inspect dumps")
    diagnostics = {name: {**cross_peer_outputs[name],
                         "zunic_hex": bytes(outputs["zunic"][name]).hex(),
                         "rust_hex": bytes(outputs["rust"][name]).hex()}
                   for name in DIAGNOSTICS}
    (output / "diagnostics.json").write_text(json.dumps(diagnostics, indent=2) + "\n")
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
            check_rows(pair[peer], outputs[peer], "strip_ansi")
            for case, operations in pair[peer].items():
                if any(row["bytes"] != len(snapshots[case]) for row in operations.values()):
                    raise RuntimeError("timed input size differs from verified input")
            print(f"completed {peer}-{name}", flush=True)
        pairs.append(pair)
    for peer, command in commands.items():
        dump = run(command + ["--dump"], HERE).stdout
        (output / f"{peer}-after.dump").write_text(dump)
        if parse_dump(dump, snapshots, "strip_ansi") != outputs[peer]:
            raise RuntimeError(f"{peer}: exact output changed during timing")
    checks_after = {peer: run(command + ["--check"], HERE).stdout for peer, command in commands.items()}
    if checks_before != checks_after:
        raise RuntimeError("stripping output changed during timing")
    corpus_hashes_after = {name: sha256(path) for name, path in zip(CORPORA + DIAGNOSTICS, corpus_paths)}
    if corpus_hashes_before != corpus_hashes_after:
        raise RuntimeError("shared corpora changed during timing")

    if source_hashes() != sources_before:
        raise RuntimeError("benchmark sources changed during the run")

    summary = create_summary(
        suite="strip_ansi", title="ANSI stripping: strip-ansi-escapes vs Zunic", label=args.label,
        pairs=pairs,
        comparisons=[{"id": z, "label": caption, "zunic": z, "rust": r}
                     for z, r, caption in PAIRED],
        peers={"zunic": {"name": "Zunic", "unicode": "not applicable (byte-only)"},
               "rust": {"name": "strip-ansi-escapes 0.2.1 (vte 0.14.1)", "unicode": "not applicable (no Unicode property tables)"}},
        contract={"input": "bytes", "consumption": "bytes_fnv1"},
        outputs={name: cross_peer_outputs[name] for name in CORPORA},
        operation_outputs=compare_operations(outputs, "strip_ansi", [
            {"id": z, "zunic": z, "rust": r} for z, r, _ in PAIRED], CORPORA),
        notes=["Input bytes to output bytes; output FNV-1a checksum and API-internal work are timed. File I/O is excluded.",
               "Reuse: both output buffers are prepared outside timing. Rust Writer construction, its internal LineWriter allocation, flushing and destruction remain timed.",
               "Allocate: both peers allocate and free output inside timing; Rust strip uses its standard Vec growth strategy.",
               "No external UTF-8 validation is added. Rust vte decoding/re-encoding is part of the API and stays timed.",
               "All timed outputs must match exactly. Diagnostic-only inputs are saved separately in diagnostics.json; differences are policy differences, not Unicode table versions.",
               "Diagnostic differences: " + ", ".join(name for name in DIAGNOSTICS if not diagnostics[name]["equal"]) + ".",
               "Corpus definitions differ from the native harness: do not compare timings across the two harnesses."],
        environment={"platform": platform.platform(), "machine": platform.machine(), "python": sys.version,
                     "zig": subprocess.check_output(["zig", "version"], text=True).strip(),
                     "rustc": subprocess.check_output(["rustc", "--version"], text=True).strip(),
                     "rustflags": env["RUSTFLAGS"]},
        provenance={"binary_hashes": {"zunic": sha256(zig_binary), "rust": sha256(rust_binary)},
                    "corpus_hashes_before": corpus_hashes_before, "corpus_hashes_after": corpus_hashes_after,
                    "checks": checks_before,
                    "git_head": run(["git", "rev-parse", "HEAD"], ROOT).stdout.strip(),
                    "git_status": run(["git", "status", "--porcelain"], ROOT).stdout,
                    "cargo_lock_sha256": sha256(HERE / "Cargo.lock"),
                    "source_hashes": sources_before,
                    "diagnostics": diagnostics},
    )
    shutil.copy2(HERE / "Cargo.lock", output / "Cargo.lock")
    for filename in ("benchmark.py", "zunic-strip-ansi.zig", "build.zig", "build.zig.zon", "cases.py", "Cargo.toml"):
        shutil.copy2(HERE / filename, output / filename)
    shutil.copy2(HERE / "src/main.rs", output / "main.rs")
    (output / "zunic.patch").write_text(run(["git", "diff", "HEAD"], ROOT).stdout)
    (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    markdown = markdown_report(summary)
    (output / "comparison.md").write_text(markdown)
    print(common_terminal_report(summary))
    print(f"Saved {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
