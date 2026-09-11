#!/usr/bin/env python3
"""Reproducible, alternating Zunic versus uucode benchmarks."""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import platform
import re
import shutil
import statistics
import subprocess
import sys
import uuid
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
CORPUS_DIR = ROOT / "bench-vs-rust" / "texts"
STANDARD_CORPORA = ("arabic", "hindi", "korean", "russian", "source_code", "english", "japanese", "mandarin")
CORPUS_PATHS = {
    name: CORPUS_DIR / f"{name}.txt"
    for name in STANDARD_CORPORA
}
CORPUS_PATHS["features"] = HERE / "texts" / "features.txt"
CORPORA = tuple(CORPUS_PATHS)
OPERATIONS = (
    "utf8", "graphemes", "measured", "width",
    "terminal_properties", "terminal_lookup", "case_fold", "grapheme_stream", "ghostty_width",
)
EXACT_OPERATIONS = ("terminal_properties", "terminal_lookup", "case_fold", "ghostty_width")
CAPTIONS = {
    "utf8": "UTF-8 decoding",
    "graphemes": "Extended grapheme ranges",
    "measured": "Grapheme ranges with cluster width",
    "width": "Whole-text grapheme width",
    "terminal_properties": "Unicode terminal property facts",
    "terminal_lookup": "Fused scalar terminal-property lookup",
    "case_fold": "Full default case folding",
    "grapheme_stream": "Incremental grapheme boundaries",
    "ghostty_width": "Ghostty scalar-width composition",
}
PEERS = {
    "zunic": {"binary": "zunic-bench", "unicode": "17.0.0"},
    "uucode": {"binary": "uucode-bench", "unicode": "17.0.0"},
}
UUCODE_COMMIT = "f67fa5dbef5c9de57773dbe2f7a02bebc7e20301"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_hashes() -> dict[str, str]:
    paths = [ROOT / "build.zig", ROOT / "build.zig.zon"]
    paths += sorted((ROOT / "src").rglob("*.zig"))
    paths += sorted(path for path in HERE.rglob("*") if path.is_file() and
                    not any(part in {".zig-cache", ".zig-global-cache", "zig-out", "benchmarks", "__pycache__"}
                            for part in path.relative_to(HERE).parts))
    return {str(path.relative_to(ROOT)): sha256(path) for path in paths}


def run(command: list[str], cwd: Path = HERE, *, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True)
    if result.returncode:
        sys.stderr.write(result.stdout)
        sys.stderr.write(result.stderr)
        result.check_returncode()
    return result


def fields(line: str) -> dict[str, str]:
    return dict(item.split("=", 1) for item in line.split() if "=" in item)


def parse_dump(text: str, snapshots: dict[str, bytes]) -> dict[str, dict[str, dict[str, object]]]:
    inputs: set[str] = set()
    outputs: dict[str, dict[str, dict[str, object]]] = {}
    for line in text.splitlines():
        row = fields(line)
        if "case" not in row:
            continue
        case = row["case"]
        if case not in snapshots:
            raise ValueError(f"unexpected case {case!r}")
        if "input" in row:
            if case in inputs or bytes.fromhex(row["input"]) != snapshots[case]:
                raise ValueError(f"{case}: duplicate or mismatched embedded input")
            inputs.add(case)
        elif {"op", "units", "checksum", "output"} <= row.keys():
            operation = row["op"]
            if operation not in OPERATIONS or operation in outputs.setdefault(case, {}):
                raise ValueError(f"{case}: unexpected or duplicate operation {operation!r}")
            outputs[case][operation] = {
                "units": int(row["units"]),
                "checksum": int(row["checksum"]),
                "output": row["output"],
            }
    if inputs != set(CORPORA) or set(outputs) != set(CORPORA):
        raise ValueError("incomplete dump")
    if any(set(rows) != set(OPERATIONS) for rows in outputs.values()):
        raise ValueError("incomplete operation dump")
    return outputs


def parse_timing(text: str, peer: str, outputs: dict[str, dict[str, dict[str, object]]], snapshots: dict[str, bytes]) -> dict[str, dict[str, object]]:
    headers = [fields(line) for line in text.splitlines() if line.startswith("protocol=")]
    expected = {"protocol": "5", "suite": "unicode", "peer": peer, "samples": "15",
                "calibration_ms": "50", "input": "bytes+predecoded_codepoints", "consumption": "operation_checksum_v5"}
    if len(headers) != 1 or any(headers[0].get(k) != v for k, v in expected.items()):
        raise ValueError(f"incompatible header for {peer}: {headers}")
    raw: dict[tuple[str, str], list[int]] = {}
    parsed: dict[str, dict[str, object]] = {}
    for line in text.splitlines():
        row = fields(line)
        if not {"case", "op"} <= row.keys():
            continue
        key = (row["case"], row["op"])
        if key[0] not in CORPORA or key[1] not in OPERATIONS:
            raise ValueError(f"unexpected timing row {key}")
        if "raw_samples=" in line:
            if key in raw:
                raise ValueError(f"duplicate samples {key}")
            raw[key] = [int(v) for v in re.findall(r"\d+", line.split("raw_samples=", 1)[1])]
            continue
        required = {"bytes", "units", "iterations", "ns", "mad", "checksum"}
        if not required <= row.keys() or key[1] in parsed.setdefault(key[0], {}):
            raise ValueError(f"invalid or duplicate result {key}")
        samples = raw.get(key, [])
        if len(samples) != 15:
            raise ValueError(f"{key}: expected 15 samples")
        median = int(statistics.median(samples))
        mad = int(statistics.median(abs(value - median) for value in samples))
        result = {
            "bytes": int(row["bytes"]), "units": int(row["units"]),
            "iterations": int(row["iterations"]), "median_ns": int(row["ns"]),
            "mad_ns": int(row["mad"]), "checksum": int(row["checksum"]),
            "samples_ns": samples,
        }
        evidence = outputs[key[0]][key[1]]
        if (result["median_ns"] != median or result["mad_ns"] != mad or
                result["bytes"] != len(snapshots[key[0]]) or
                result["units"] != evidence["units"] or result["checksum"] != evidence["checksum"]):
            raise ValueError(f"{key}: timed result differs from samples or dump")
        parsed[key[0]][key[1]] = result
    if set(parsed) != set(CORPORA) or any(set(rows) != set(OPERATIONS) for rows in parsed.values()):
        raise ValueError("incomplete timing output")
    return parsed


def median_row(summary: dict, peer: str, case: str, operation: str) -> dict[str, object]:
    rows = [pair["results"][peer][case][operation] for pair in summary["pairs"]]
    return {"median_ns": statistics.median(row["median_ns"] for row in rows), "units": rows[0]["units"]}


def report(summary: dict, markdown: bool) -> str:
    lines = [f"# {summary['title']}" if markdown else summary["title"], ""]
    if markdown:
        lines += [f"Label: `{summary['label']}`. Sequential alternating pairs: {summary['pair_count']}.", "",
                  f"Unicode: Zunic {summary['peers']['zunic']['unicode']}; uucode {summary['peers']['uucode']['unicode']}.", ""]
    else:
        lines += [f"Label: {summary['label']}; pairs: {summary['pair_count']}",
                  f"Unicode: Zunic {summary['peers']['zunic']['unicode']}; uucode {summary['peers']['uucode']['unicode']}.", ""]
    for operation in summary["operations"]:
        if markdown:
            lines += [f"## {CAPTIONS[operation]}", "", "| Corpus | Zunic µs | uucode µs | uucode/Zunic | Units Z/U | Output |",
                      "| --- | ---: | ---: | ---: | ---: | :---: |"]
        else:
            lines += [CAPTIONS[operation], "corpus              Zunic µs  uucode µs  U/Z     units Z/U       output"]
        for case in summary["cases"]:
            z = median_row(summary, "zunic", case, operation)
            u = median_row(summary, "uucode", case, operation)
            equality = summary["operation_outputs"][operation][case]["equal"]
            status = "same" if equality else "diff"
            if markdown:
                lines.append(f"| {case} | {z['median_ns']/1000:.3f} | {u['median_ns']/1000:.3f} | {u['median_ns']/z['median_ns']:.2f}× | {z['units']}/{u['units']} | {status} |")
            else:
                lines.append(f"{case:<18} {z['median_ns']/1000:>9.3f} {u['median_ns']/1000:>10.3f} {u['median_ns']/z['median_ns']:>6.2f}× {z['units']:>7}/{u['units']:<7} {status}")
        lines.append("")
    lines.extend(["Ratio = uucode time / Zunic time; above 1 means Zunic took less time.",
                  "Exact output records are compared before and after timing; differences are reported rather than treated as benchmark failures.",
                  *summary["notes"]])
    return "\n".join(lines) + "\n"


def self_test() -> int:
    snapshots = {name: path.read_bytes() for name, path in CORPUS_PATHS.items()}
    outputs = {}
    for peer, metadata in PEERS.items():
        binary = HERE / "zig-out" / "bin" / metadata["binary"]
        for args in ([], ["--help"], ["-h"]):
            result = run([str(binary), *args], Path("/"))
            if "Usage:" not in result.stdout or "protocol=5" in result.stdout:
                raise ValueError(f"{peer}: bad help output")
        dump = run([str(binary), "--dump"], Path("/")).stdout
        outputs[peer] = parse_dump(dump, snapshots)
        bad = subprocess.run([str(binary), "--unknown"], cwd="/", capture_output=True, text=True)
        if bad.returncode == 0:
            raise ValueError(f"{peer}: unknown option succeeded")
    for case in CORPORA:
        for operation in EXACT_OPERATIONS:
            if outputs["zunic"][case][operation] != outputs["uucode"][case][operation]:
                raise ValueError(f"{case}/{operation}: peers produced different exact results")
    for case in STANDARD_CORPORA:
        if outputs["zunic"][case]["grapheme_stream"] != outputs["uucode"][case]["grapheme_stream"]:
            raise ValueError(f"{case}/grapheme_stream: unexpected corpus boundary difference")
    if outputs["zunic"]["features"]["grapheme_stream"] == outputs["uucode"]["features"]["grapheme_stream"]:
        raise ValueError("features/grapheme_stream: expected modifier-tailoring difference disappeared")
    print("CLI, exact dumps, and new-operation contract checks passed for both peers")
    return 0


def benchmark(args: argparse.Namespace) -> int:
    env = dict(os.environ, ZIG_GLOBAL_CACHE_DIR=str(HERE / ".zig-global-cache"))
    if not args.skip_build:
        run(["zig", "build", "-Doptimize=ReleaseFast", "-Dcpu=native", "--summary", "all"], env=env)
    corpus_paths = dict(CORPUS_PATHS)
    corpus_hashes_before = {name: sha256(path) for name, path in corpus_paths.items()}

    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    output = HERE / "benchmarks" / f"{stamp}-{args.label}-{uuid.uuid4().hex[:6]}"
    binary_dir, text_dir = output / "bin", output / "texts"
    binary_dir.mkdir(parents=True)
    text_dir.mkdir()
    commands: dict[str, list[str]] = {}
    for peer, metadata in PEERS.items():
        destination = binary_dir / metadata["binary"]
        shutil.copy2(HERE / "zig-out" / "bin" / metadata["binary"], destination)
        commands[peer] = [str(destination)]
    for name, path in corpus_paths.items():
        shutil.copy2(path, text_dir / path.name)
    snapshots = {name: (text_dir / f"{name}.txt").read_bytes() for name in CORPORA}

    outputs = {}
    for peer in PEERS:
        dump = run(commands[peer] + ["--dump"]).stdout
        (output / f"{peer}-before.dump").write_text(dump)
        outputs[peer] = parse_dump(dump, snapshots)
    operation_outputs = {operation: {case: {
        "equal": outputs["zunic"][case][operation]["output"] == outputs["uucode"][case][operation]["output"],
        "zunic_count": outputs["zunic"][case][operation]["units"],
        "uucode_count": outputs["uucode"][case][operation]["units"],
    } for case in CORPORA} for operation in OPERATIONS}
    for operation in EXACT_OPERATIONS:
        for case in CORPORA:
            if not operation_outputs[operation][case]["equal"]:
                raise RuntimeError(f"{case}/{operation}: peers produced different exact results")

    pairs = []
    for index in range(args.pairs):
        pair_name = chr(ord("a") + index)
        order = ("zunic", "uucode") if index % 2 == 0 else ("uucode", "zunic")
        pair = {"name": pair_name, "order": list(order), "results": {}}
        for peer in order:
            print(f"starting {peer}-{pair_name}", flush=True)
            result = run(commands[peer] + ["--bench"])
            (output / f"{peer}-{pair_name}.stdout.txt").write_text(result.stdout)
            (output / f"{peer}-{pair_name}.stderr.txt").write_text(result.stderr)
            pair["results"][peer] = parse_timing(result.stdout, peer, outputs[peer], snapshots)
            print(f"completed {peer}-{pair_name}", flush=True)
        pairs.append(pair)

    for peer in PEERS:
        dump = run(commands[peer] + ["--dump"]).stdout
        (output / f"{peer}-after.dump").write_text(dump)
        if parse_dump(dump, snapshots) != outputs[peer]:
            raise RuntimeError(f"{peer}: output changed during timing")
    corpus_hashes_after = {name: sha256(path) for name, path in corpus_paths.items()}
    if corpus_hashes_before != corpus_hashes_after:
        raise RuntimeError("shared corpora changed during timing")

    git_head = run(["git", "rev-parse", "HEAD"], ROOT).stdout.strip()
    git_status = run(["git", "status", "--short"], ROOT).stdout
    summary = {
        "schema": "zunic-uucode-benchmark/v5", "title": "Unicode primitives: uucode vs Zunic",
        "label": args.label, "pair_count": args.pairs, "cases": list(CORPORA),
        "operations": list(OPERATIONS), "pairs": pairs,
        "peers": {name: {"name": name if name == "zunic" else "uucode 0.2.0",
                          "unicode": metadata["unicode"]} for name, metadata in PEERS.items()},
        "contract": {"input": "bytes+predecoded_codepoints", "consumption": "operation_checksum_v5"},
        "operation_outputs": operation_outputs,
        "notes": [
            "Inputs are valid UTF-8 and file I/O is outside timing.",
            "Measured traversal consumes each grapheme's start, end, and width; Zunic's renderable flag has no uucode counterpart and is excluded.",
            "Both peers use Unicode 17.0.0; whole-grapheme width policies can still differ and are shown explicitly.",
            "Terminal-property, full-fold, and Ghostty-width rows agree exactly on these valid UTF-8 corpora.",
            "The fused scalar lookup row receives predecoded code points, excluding UTF-8 decoding from its timing.",
            "Multi-result operations use independent field accumulators, combined once after traversal, to reduce checksum dependency-chain cost.",
            "The focused streaming row intentionally records uucode's emoji-modifier tailoring against Zunic's default UAX #29 GB9 behavior.",
        ],
        "environment": {"platform": platform.platform(), "machine": platform.machine(), "python": sys.version,
                        "zig": run(["zig", "version"]).stdout.strip()},
        "provenance": {"git_head": git_head, "git_status": git_status,
                       "uucode_commit": UUCODE_COMMIT,
                       "binary_hashes": {peer: sha256(binary_dir / metadata["binary"]) for peer, metadata in PEERS.items()},
                       "binary_sizes": {peer: (binary_dir / metadata["binary"]).stat().st_size for peer, metadata in PEERS.items()},
                       "source_hashes": source_hashes(),
                       "corpus_hashes_before": corpus_hashes_before, "corpus_hashes_after": corpus_hashes_after},
    }
    (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    markdown = report(summary, True)
    (output / "comparison.md").write_text(markdown)
    print(report(summary, False), end="")
    print(f"Saved {output}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pairs", type=int, choices=(1, 3), default=3)
    parser.add_argument("--label", default="uucode")
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if args.report:
        summary = json.loads(args.report.read_text())
        if summary.get("schema") not in {"zunic-uucode-benchmark/v1", "zunic-uucode-benchmark/v2", "zunic-uucode-benchmark/v3", "zunic-uucode-benchmark/v4", "zunic-uucode-benchmark/v5"}:
            raise ValueError("unsupported summary schema")
        print(report(summary, True), end="")
        return 0
    return benchmark(args)


if __name__ == "__main__":
    raise SystemExit(main())
