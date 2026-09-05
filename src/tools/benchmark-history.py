#!/usr/bin/env python3
"""Save and compare immutable local zunic benchmark runs."""
import argparse
import datetime as dt
import hashlib
import json
import os
import platform
import re
import shlex
import statistics
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HISTORY = ROOT / "private" / "benchmarks"
SAFE_LABEL = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}\Z")

def digest_sources():
    paths = [ROOT / "Makefile", ROOT / "build.zig", ROOT / "build.zig.zon"]
    paths += sorted((ROOT / "src").rglob("*.zig"))
    paths += [Path(__file__)]
    h = hashlib.sha256()
    for path in paths:
        if path.exists() and "private" not in path.parts and "plans" not in path.parts:
            h.update(str(path.relative_to(ROOT)).encode() + b"\0")
            h.update(path.read_bytes())
    return h.hexdigest()

def git(*args):
    try:
        return subprocess.check_output(["git", *args], cwd=ROOT, text=True, stderr=subprocess.DEVNULL).strip()
    except (OSError, subprocess.CalledProcessError):
        return None

def parse_samples(stdout):
    samples = {}
    header = {}
    for line in stdout.splitlines():
        fields = dict(part.split("=", 1) for part in line.split() if "=" in part)
        if line.startswith("zunic-benchmark"):
            header = fields
        elif "case" in fields and "operation" in fields:
            key = (fields["case"], fields["operation"], fields.get("traversal", "full"))
            samples.setdefault(key, []).append(fields)
    return header, samples

def summarize(samples):
    result = {}
    for key, values in samples.items():
        ns = sorted(int(v["elapsed_ns"]) for v in values)
        median = statistics.median(ns)
        spread = 0 if median == 0 else (ns[-1] - ns[0]) / median
        result["/".join(key)] = {"median_ns": median, "spread": spread, "checksum": values[0]["checksum"], "samples": ns}
    return result

def save(args):
    if not SAFE_LABEL.fullmatch(args.label):
        raise SystemExit("label must contain only letters, digits, dot, underscore, or dash")
    build_args = shlex.split(os.environ.get("ZUNIC_BENCHMARK_BUILD_ARGS", ""))
    command = ["zig", "build", "benchmark", "-Doptimize=ReleaseFast", *build_args, "--", *args.benchmark_args]
    completed = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
    timestamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    HISTORY.mkdir(parents=True, exist_ok=True)
    run = HISTORY / f"{timestamp}-{args.label}-{os.urandom(3).hex()}"
    run.mkdir()
    (run / "stdout.txt").write_text(completed.stdout)
    (run / "stderr.txt").write_text(completed.stderr)
    header, samples = parse_samples(completed.stdout)
    metadata = {
        "format": 1, "created_utc": timestamp, "label": args.label,
        "command": command, "returncode": completed.returncode,
        "git_head": git("rev-parse", "HEAD") or "unknown",
        "git_dirty": bool(git("status", "--porcelain")),
        "source_fingerprint": digest_sources(), "python": platform.python_version(),
        "os": platform.platform(), "machine": platform.machine(),
        "cpu": platform.processor() or "unknown", "zig": git_zig_version(),
        "harness": header, "benchmark_args": args.benchmark_args, "build_args": build_args,
    }
    (run / "metadata.json").write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n")
    (run / "summary.json").write_text(json.dumps(summarize(samples), indent=2, sort_keys=True) + "\n")
    print(run)
    if completed.returncode:
        raise SystemExit(completed.returncode)

def git_zig_version():
    try:
        return subprocess.check_output(["zig", "version"], text=True).strip()
    except (OSError, subprocess.CalledProcessError):
        return "unknown"

def load_run(path):
    path = Path(path)
    return json.loads((path / "metadata.json").read_text()), json.loads((path / "summary.json").read_text())

def compare(args):
    before_meta, before = load_run(args.before)
    after_meta, after = load_run(args.after)
    for key in ("zig", "machine", "benchmark_args"):
        if before_meta.get(key) != after_meta.get(key):
            raise SystemExit(f"incompatible runs: {key} differs")
    before_harness = {k: v for k, v in before_meta["harness"].items() if k != "wrap_fast_path"}
    after_harness = {k: v for k, v in after_meta["harness"].items() if k != "wrap_fast_path"}
    if before_harness != after_harness:
        raise SystemExit("incompatible runs: harness metadata differs")
    for key in sorted(set(before) | set(after)):
        if key not in before or key not in after:
            print(f"case={key} status=missing")
            continue
        old, new = before[key], after[key]
        equal = old["checksum"] == new["checksum"]
        change = 100 * (new["median_ns"] - old["median_ns"]) / old["median_ns"] if old["median_ns"] else 0
        status = "equivalent" if equal else "output-changed"
        print(f"case={key} status={status} before_median_ns={old['median_ns']} after_median_ns={new['median_ns']} change_percent={change:.2f} before_spread={old['spread']:.3f} after_spread={new['spread']:.3f}")

def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(required=True)
    save_parser = sub.add_parser("save")
    save_parser.add_argument("--label", required=True)
    save_parser.add_argument("benchmark_args", nargs="*")
    save_parser.set_defaults(func=save)
    compare_parser = sub.add_parser("compare")
    compare_parser.add_argument("--before", required=True)
    compare_parser.add_argument("--after", required=True)
    compare_parser.set_defaults(func=compare)
    args = parser.parse_args()
    args.func(args)

if __name__ == "__main__":
    main()
