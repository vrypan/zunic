#!/usr/bin/env python3
"""Immutable, alternating Zunic-machine versus unicode-linebreak benchmark."""
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
import unittest
import uuid
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from benchmark_contract import parse_timing, parse_dump, check_rows, compare_operations
from benchmark_report import create_summary, markdown_report, terminal_report as common_terminal_report

ROOT = HERE.parents[1]
CORPORA = ("arabic", "hindi", "korean", "russian", "source_code", "english", "japanese", "mandarin")
OPS = ("opportunities_only", "decode_classify")
OPS_BY_PEER = {
    "zunic": ("all_boundaries", "opportunities_only", "decode_classify",
              "preclassified_rules", "wrap_full", "wrap_24"),
    "rust": OPS,
}
SAMPLES = 15
TARGET = 1 / 1.20
def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def hashes(paths: list[Path], base: Path) -> dict[str, str]:
    return {str(path.relative_to(base)): sha256(path) for path in sorted(paths)}


def cpu_description() -> str:
    if sys.platform == "darwin":
        result = subprocess.run(["sysctl", "-n", "machdep.cpu.brand_string"], capture_output=True, text=True)
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()
    if Path("/proc/cpuinfo").exists():
        for line in Path("/proc/cpuinfo").read_text().splitlines():
            if line.startswith(("model name", "Hardware")):
                return line.split(":", 1)[1].strip()
    return platform.processor() or "unknown"


def run_logged(command: list[str], cwd: Path, output: Path, env=None) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True)
    output.write_text(result.stdout + result.stderr)
    result.check_returncode()
    return result


def parse_run(text: str) -> dict[str, dict[str, dict[str, object]]]:
    header = next((line for line in text.splitlines() if line.startswith("protocol=")), "")
    peer = dict(field.split("=", 1) for field in header.split() if "=" in field).get("peer")
    return parse_timing(text, suite="linebreak", peer=peer, cases=CORPORA,
                        operations=OPS_BY_PEER[peer])


def parse_streams(text: str) -> dict[str, str]:
    result = {}
    for line in text.splitlines():
        if line.startswith("case=") and " stream=" in line:
            prefix, stream = line.split(" stream=", 1)
            result[prefix.removeprefix("case=")] = stream
    return result


def validate_summary(summary: dict, require_three: bool = True) -> list[str]:
    if summary.get("schema") == "zunic-rust-benchmark/v1":
        provenance = summary.get("provenance", {})
        summary = {
            "pair_count": summary.get("pair_count"),
            "pairs": [dict(pair["results"], name=pair["name"]) for pair in summary.get("pairs", [])],
            "corpus_hashes_before": provenance.get("corpus_hashes_before"),
            "corpus_hashes_after": provenance.get("corpus_hashes_after"),
            "source_hashes_before": provenance.get("source_hashes_before"),
            "source_hashes_after": provenance.get("source_hashes_after"),
        }
    errors: list[str] = []
    expected_pairs = 3 if require_three else summary.get("pair_count", 0)
    if summary.get("pair_count") != expected_pairs:
        errors.append(f"expected {expected_pairs} pairs, got {summary.get('pair_count')}")
    if summary.get("corpus_hashes_before") != summary.get("corpus_hashes_after"):
        errors.append("corpus hashes changed")
    if summary.get("source_hashes_before") != summary.get("source_hashes_after"):
        errors.append("source hashes changed")
    pairs = summary.get("pairs", [])
    if len(pairs) != expected_pairs:
        errors.append(f"expected {expected_pairs} pair records, got {len(pairs)}")
    for pair in pairs:
        for case in CORPORA:
            try:
                z = pair["zunic"][case]["opportunities_only"]
                r = pair["rust"][case]["opportunities_only"]
            except KeyError:
                errors.append(f"{pair.get('name', '?')}/{case}: missing result")
                continue
            for peer in ("zunic", "rust"):
                for op in OPS:
                    row = pair.get(peer, {}).get(case, {}).get(op)
                    if row is None:
                        errors.append(f"{pair['name']}/{case}/{peer}/{op}: missing result")
                    elif len(row.get("samples_ns", [])) != SAMPLES:
                        errors.append(f"{pair['name']}/{case}/{peer}/{op}: incomplete samples")
            ratio = r["median_ns"] / z["median_ns"]
            if ratio < TARGET:
                errors.append(f"{pair['name']}/{case}: Rust/Zunic {ratio:.6f} < {TARGET:.6f}")
    return errors


def source_paths() -> list[Path]:
    paths = list((ROOT / "src").rglob("*.zig")) + list((ROOT / "src/tools").glob("*.py"))
    paths += [ROOT / "build.zig", ROOT / "build.zig.zon", HERE / "build.zig", HERE / "build.zig.zon",
              HERE / "diagnostic.zig", HERE / "diagnostic.rs", HERE / "diagnostic-rust/Cargo.toml",
              HERE / "diagnostic-rust/Cargo.lock", Path(__file__).resolve(),
              HERE.parent / "benchmark_contract.py", HERE.parent / "benchmark_report.py",
              HERE.parent / "benchmark_table.py"]
    return [path for path in paths if path.exists()]


def collect(label: str, pair_count: int) -> Path:
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out = ROOT / "bench-vs-rust/benchmarks" / f"{stamp}-{label}-{uuid.uuid4().hex[:6]}"
    out.mkdir(parents=True)
    env = dict(os.environ, RUSTFLAGS="-C target-cpu=native")
    zig_build = ["zig", "build", "install-diagnostic", "-Doptimize=ReleaseFast", "-Dcpu=native", "--summary", "all"]
    rust_build = ["cargo", "build", "--locked", "--release", "--manifest-path", str(HERE / "diagnostic-rust/Cargo.toml")]
    run_logged(zig_build, HERE, out / "zig-build.txt")
    run_logged(rust_build, HERE, out / "rust-build.txt", env)
    bins = out / "bin"
    bins.mkdir()
    zig = bins / "line-break-diagnostic"
    rust = bins / "rust-line-break-diagnostic"
    shutil.copy2(HERE / "zig-out/bin/line-break-diagnostic", zig)
    shutil.copy2(HERE / "diagnostic-rust/target/release/diagnostic", rust)
    sources_before = hashes(source_paths(), ROOT)
    snapshot = out / "source-snapshot"
    for path in source_paths():
        destination = snapshot / path.relative_to(ROOT)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, destination)
    corpus_paths = [HERE.parent / f"texts/{name}.txt" for name in CORPORA]
    corpus_before = hashes(corpus_paths, ROOT)
    commands = {"zunic": [str(zig)], "rust": [str(rust), str(HERE.parent / "texts")]}
    streams = {}
    outputs = {}
    snapshots = {name: (HERE.parent / f"texts/{name}.txt").read_bytes() for name in CORPORA}
    for peer in ("zunic", "rust"):
        result = subprocess.run(commands[peer] + ["--dump"], cwd=HERE, capture_output=True, text=True, check=True)
        (out / f"{peer}-streams-before.txt").write_text(result.stdout)
        outputs[peer] = parse_dump(result.stdout, snapshots, "linebreak")
        streams[peer] = parse_streams(result.stdout)
        if set(streams[peer]) != set(CORPORA):
            raise RuntimeError(f"{peer}: incomplete stream output")
    cross = {}
    for case in CORPORA:
        z_events = [event for event in streams["zunic"][case].split(",") if event]
        r_events = [event for event in streams["rust"][case].split(",") if event]
        first_difference = next((index for index, values in enumerate(zip(z_events, r_events))
                                 if values[0] != values[1]), min(len(z_events), len(r_events)))
        if z_events == r_events:
            first_difference = None
        cross[case] = {
            "equal": z_events == r_events, "zunic_event_count": len(z_events),
            "rust_event_count": len(r_events), "first_difference_index": first_difference,
            "zunic_first_difference": None if first_difference is None or first_difference >= len(z_events) else z_events[first_difference],
            "rust_first_difference": None if first_difference is None or first_difference >= len(r_events) else r_events[first_difference],
            "zunic_sha256": hashlib.sha256(streams["zunic"][case].encode()).hexdigest(),
            "rust_sha256": hashlib.sha256(streams["rust"][case].encode()).hexdigest(),
        }
    pairs = []
    for index in range(pair_count):
        name = chr(ord("a") + index)
        order = ("zunic", "rust") if index % 2 == 0 else ("rust", "zunic")
        pair = {"name": name}
        for peer in order:
            print(f"starting {peer}-{name}", flush=True)
            result = subprocess.run(commands[peer] + ["--bench"], cwd=HERE, capture_output=True, text=True)
            (out / f"{peer}-{name}.stdout.txt").write_text(result.stdout)
            (out / f"{peer}-{name}.stderr.txt").write_text(result.stderr)
            result.check_returncode()
            header = next((line for line in result.stdout.splitlines() if line.startswith("protocol=")), "")
            header_fields = dict(field.split("=", 1) for field in header.split() if "=" in field)
            if peer == "zunic" and header_fields.get("engine") != "zunic-machine":
                raise RuntimeError("Zunic diagnostic did not assert the machine engine")
            pair[peer] = parse_run(result.stdout)
            check_rows(pair[peer], outputs[peer], "linebreak")
            print(f"completed {peer}-{name}", flush=True)
        pairs.append(pair)
    for peer in ("zunic", "rust"):
        result = subprocess.run(commands[peer] + ["--dump"], cwd=HERE, capture_output=True, text=True, check=True)
        (out / f"{peer}-streams-after.txt").write_text(result.stdout)
        if parse_dump(result.stdout, snapshots, "linebreak") != outputs[peer] or parse_streams(result.stdout) != streams[peer]:
            raise RuntimeError(f"{peer}: emitted stream changed during timing")
    source_after = hashes(source_paths(), ROOT)
    corpus_after = hashes(corpus_paths, ROOT)
    if sources_before != source_after or corpus_before != corpus_after:
        raise RuntimeError("source or corpus changed during timing")
    validation_view = {"pair_count": pair_count, "pairs": pairs,
                       "source_hashes_before": sources_before, "source_hashes_after": source_after,
                       "corpus_hashes_before": corpus_before, "corpus_hashes_after": corpus_after}
    near_parity_pass = not validate_summary(validation_view, require_three=False) and pair_count == 3
    summary = create_summary(
        suite="linebreak", title="Line breaking: unicode-linebreak vs Zunic", label=label, pairs=pairs,
        comparisons=[{"id": "opportunities", "label": "Line-break opportunities",
                      "zunic": "opportunities_only", "rust": "opportunities_only"}],
        peers={"zunic": {"name": "Zunic", "unicode": "17.0.0"},
               "rust": {"name": "unicode-linebreak 0.1.5", "unicode": "15.0.0 with SA tailoring"}},
        contract={"input": "bytes", "consumption": "offset_status_checksum_v1"}, outputs=cross,
        operation_outputs=compare_operations(outputs, "linebreak", [
            {"id": "opportunities", "zunic": "opportunities_only", "rust": "opportunities_only"}], CORPORA),
        notes=["Unicode-version discrepancies are accepted; opportunity differences are reported.",
               "UTF-8 validation/decoding and the opportunity checksum are timed; file I/O is excluded."],
        environment={"platform": platform.platform(), "machine": platform.machine(),
                     "processor": cpu_description(), "python": sys.version,
                     "zig": subprocess.check_output(["zig", "version"], text=True).strip(),
                     "rustc": subprocess.check_output(["rustc", "--version"], text=True).strip(),
                     "rustflags": env["RUSTFLAGS"]},
        provenance={"acceptance_eligible": pair_count == 3, "near_parity_pass": near_parity_pass,
                    "threshold_rust_over_zunic": TARGET,
                    "commands": {"zig_build": zig_build, "rust_build": rust_build, "runs": commands},
                    "binary_hashes": {"zunic": sha256(zig), "rust": sha256(rust)},
                    "source_hashes_before": sources_before, "source_hashes_after": source_after,
                    "corpus_hashes_before": corpus_before, "corpus_hashes_after": corpus_after,
                    "corpus_sizes": {name: (HERE.parent / f"texts/{name}.txt").stat().st_size for name in CORPORA}},
    )
    (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    (out / "comparison.md").write_text(markdown_report(summary))
    print(common_terminal_report(summary), flush=True)
    print(f"saved {out}", flush=True)
    return out


class SyntheticTests(unittest.TestCase):
    def record(self, ratio=0.9, samples=SAMPLES):
        row = {"median_ns": 100, "mad_ns": 1, "units": 2, "samples_ns": [100] * samples}
        rust = dict(row, median_ns=round(100 * ratio))
        pair = {"name": "a", "zunic": {case: {op: row for op in OPS} for case in CORPORA},
                "rust": {case: {op: rust for op in OPS} for case in CORPORA}}
        return {"pair_count": 1, "pairs": [pair], "corpus_hashes_before": {"x": "a"}, "corpus_hashes_after": {"x": "a"},
                "source_hashes_before": {"x": "a"}, "source_hashes_after": {"x": "a"}}

    def test_known_ratios(self):
        self.assertEqual([], validate_summary(self.record(), False))
        self.assertTrue(any("Rust/Zunic" in e for e in validate_summary(self.record(0.8), False)))

    def test_missing_pairs(self):
        self.assertTrue(validate_summary(self.record(), True))

    def test_changed_corpus(self):
        data = self.record(); data["corpus_hashes_after"] = {"x": "b"}
        self.assertIn("corpus hashes changed", validate_summary(data, False))

    def test_incomplete_samples(self):
        data = self.record(samples=14)
        self.assertTrue(any("incomplete samples" in e for e in validate_summary(data, False)))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--label")
    parser.add_argument("--pairs", type=int, choices=(1, 3), default=3)
    parser.add_argument("--check-target", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        suite = unittest.defaultTestLoader.loadTestsFromTestCase(SyntheticTests)
        return 0 if unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful() else 1
    if args.check_target:
        errors = validate_summary(json.loads((args.check_target / "summary.json").read_text()), True)
        for error in errors: print(error, file=sys.stderr)
        return 1 if errors else 0
    if not args.label:
        parser.error("--label is required when collecting a run")
    collect(args.label, args.pairs)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
