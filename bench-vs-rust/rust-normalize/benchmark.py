#!/usr/bin/env python3
"""Rebuild, verify, snapshot, and time NFC/NFD scalar iterators sequentially."""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import uuid

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE.parent))
from benchmark_contract import fields, parse_timing
from benchmark_report import create_summary, markdown_report, terminal_report as common_terminal_report
TEXTS = HERE.parent / "texts"
CORPORA = ("arabic", "hindi", "korean", "russian", "source_code", "english", "japanese", "mandarin")
EXPECTED = {(case, form) for case in CORPORA for form in ("nfc", "nfd")}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command, env=None):
    result = subprocess.run(command, cwd=HERE, env=env, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(f"{command}:\n{result.stdout}\n{result.stderr}")
    return result.stdout


def check_dump(text, snapshots):
    outputs = {}
    for line in text.splitlines():
        row = fields(line)
        key = (row["case"], row["form"])
        if key in outputs or key not in EXPECTED:
            raise ValueError(f"unexpected or duplicate dump row: {key}")
        if bytes.fromhex(row["input"]) != snapshots[key[0]]:
            raise ValueError(f"embedded/runtime corpus mismatch: {key}")
        outputs[key] = bytes.fromhex(row["hex"])
    if outputs.keys() != EXPECTED:
        raise ValueError("incomplete dump")
    return outputs


def parse(text, outputs, snapshots, expected_input="bytes"):
    header = next(fields(line) for line in text.splitlines() if line.startswith("protocol="))
    peer = header.get("peer")
    nested = parse_timing(text, suite="normalize", peer=peer, cases=CORPORA,
                          operations=("nfc", "nfd"), expected_input=expected_input)
    rows = {}
    for case in CORPORA:
        for operation in ("nfc", "nfd"):
            key = (case, operation)
            row = nested[case][operation]
            normalized = outputs[key].decode("utf-8")
            expected_sum = sum(map(ord, normalized)) % (1 << 64)
            if (row["checksum"] != expected_sum or row["units"] != len(normalized) or
                    row["bytes"] != len(snapshots[case])):
                raise ValueError(f"timed result differs from verified output: {key}")
            rows[f"{case}/{operation}"] = row
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--label", default="normalize-repaired")
    parser.add_argument("--rust-input", choices=("bytes", "prevalidated"), default="bytes",
                        help="bytes is the primary comparison; prevalidated is a diagnostic")
    parser.add_argument("--pairs", type=int, choices=(1, 3), default=3)
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9._-]{1,64}", args.label):
        parser.error("invalid label")
    zig_env = dict(os.environ, ZIG_GLOBAL_CACHE_DIR=str(HERE / ".zig-global-cache"))
    rust_env = dict(os.environ, RUSTFLAGS="-C target-cpu=native")
    commands = [["zig", "build", "-Doptimize=ReleaseFast", "-Dcpu=native"],
                ["cargo", "build", "--locked", "--release"]]
    print("Building native release peers", flush=True)
    for command, env in zip(commands, (zig_env, rust_env)):
        run(command, env)
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    dest = ROOT / "bench-vs-rust/benchmarks" / f"{stamp}-{args.label}-{uuid.uuid4().hex[:6]}"
    (dest / "bin").mkdir(parents=True)
    shutil.copytree(TEXTS, dest / "texts")
    sources = dest / "source"
    shutil.copytree(ROOT / "src", sources / "src", ignore=shutil.ignore_patterns("__pycache__"))
    for name in ("build.zig", "build.zig.zon"):
        shutil.copy2(ROOT / name, sources / name)
    harness = sources / "bench-vs-rust/rust-normalize"
    harness.mkdir(parents=True)
    shutil.copytree(TEXTS, sources / "bench-vs-rust/texts")
    for name in ("benchmark_contract.py", "benchmark_report.py", "benchmark_table.py"):
        shutil.copy2(HERE.parent / name, sources / "bench-vs-rust" / name)
    for name in ("build.zig", "build.zig.zon", "Cargo.toml", "Cargo.lock", "zunic-normalize.zig", "benchmark.py", "README.md", "differential.py"):
        shutil.copy2(HERE / name, harness / name)
    shutil.copytree(HERE / "src", harness / "src")
    snapshots = {case: (dest / "texts" / f"{case}.txt").read_bytes() for case in CORPORA}
    binaries = {"zunic": dest / "bin/zunic-normalize", "rust": dest / "bin/unicode-normalization-zunic"}
    shutil.copy2(HERE / "zig-out/bin/zunic-normalize", binaries["zunic"])
    shutil.copy2(HERE / "target/release/unicode-normalization-zunic", binaries["rust"])
    peers = {"zunic": [str(binaries["zunic"])], "rust": [str(binaries["rust"]), str(dest / "texts")]}
    run_state = {"rust_input": args.rust_input, "zunic_input": "bytes",
               "pair_count": args.pairs, "platform": platform.platform(),
               "zig": run(["zig", "version"]).strip(), "rustc": run(["rustc", "-vV"]),
               "zig_target": "native", "rustflags": rust_env["RUSTFLAGS"], "commands": commands,
               "git_head": run(["git", "rev-parse", "HEAD"]).strip(),
               "binary_hashes": {peer: sha(path) for peer, path in binaries.items()},
               "corpus_hashes": {case: hashlib.sha256(data).hexdigest() for case, data in snapshots.items()},
               "source_hashes": {str(path.relative_to(sources)): sha(path) for path in sources.rglob("*") if path.is_file()},
               "uptime_before": run(["uptime"]), "pairs": []}
    try:
        run_state["processes_before"] = run(["ps", "-Ao", "pid,pcpu,comm"])
    except (OSError, RuntimeError) as error:
        run_state["processes_before"] = str(error)
    before = {}
    for peer, command in peers.items():
        dump = run(command + ["--dump"])
        (dest / f"{peer}-before.dump").write_text(dump)
        before[peer] = check_dump(dump, snapshots)
    if before["zunic"] != before["rust"]:
        raise ValueError("normalized output differs before timing")
    print(f"Verified input and output bytes; saving {dest}", flush=True)
    for index in range(args.pairs):
        name = chr(ord("a") + index)
        order = ("zunic", "rust") if index % 2 == 0 else ("rust", "zunic")
        pair = {"name": name, "order": order}
        for peer in order:
            print(f"Starting {peer}-{name}", flush=True)
            mode = "--bench-prevalidated" if peer == "rust" and args.rust_input == "prevalidated" else "--bench"
            text = run(peers[peer] + [mode])
            (dest / f"{peer}-{name}.stdout.txt").write_text(text)
            pair[peer] = parse(text, before[peer], snapshots, args.rust_input if peer == "rust" else "bytes")
            print(f"Completed {peer}-{name}", flush=True)
        run_state["pairs"].append(pair)
    for peer, command in peers.items():
        dump = run(command + ["--dump"])
        (dest / f"{peer}-after.dump").write_text(dump)
        if check_dump(dump, snapshots) != before[peer] or sha(binaries[peer]) != run_state["binary_hashes"][peer]:
            raise ValueError("peer changed during timing")
    if any((TEXTS / f"{case}.txt").read_bytes() != data for case, data in snapshots.items()):
        raise ValueError("corpora changed during timing")
    run_state["uptime_after"] = run(["uptime"])
    outputs = {case: {"equal": all(before["zunic"][(case, form)] == before["rust"][(case, form)]
                                           for form in ("nfc", "nfd")),
                      "zunic_count": 2, "rust_count": 2} for case in CORPORA}
    summary = create_summary(
        suite="normalize", title="Canonical normalization", label=args.label,
        pairs=run_state["pairs"],
        comparisons=[{"id": form, "label": form.upper(), "zunic": form, "rust": form}
                     for form in ("nfc", "nfd")],
        peers={"zunic": {"name": "Zunic", "unicode": "16.0.0"},
               "rust": {"name": "unicode-normalization 0.1.24", "unicode": "16.0.0"}},
        contract={"input": "bytes" if args.rust_input == "bytes" else "zunic=bytes,rust=prevalidated",
                  "consumption": "scalar_sum_v1"}, outputs=outputs,
        operation_outputs={form: {case: {
            "equal": before["zunic"][(case, form)] == before["rust"][(case, form)],
            "zunic_count": len(before["zunic"][(case, form)].decode("utf-8")),
            "rust_count": len(before["rust"][(case, form)].decode("utf-8")),
        } for case in CORPORA} for form in ("nfc", "nfd")},
        notes=["UTF-8 validation is timed in the primary bytes workload; file I/O and output encoding are excluded."],
        environment={key: run_state[key] for key in ("platform", "zig", "rustc", "zig_target", "rustflags")},
        provenance={key: run_state[key] for key in ("commands", "git_head", "binary_hashes", "corpus_hashes",
                                                     "source_hashes", "uptime_before", "uptime_after", "processes_before")},
    )
    (dest / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    markdown = markdown_report(summary)
    (dest / "comparison.md").write_text(markdown)
    print(common_terminal_report(summary), flush=True)
    print(f"Saved {dest}", flush=True)


if __name__ == "__main__":
    main()
