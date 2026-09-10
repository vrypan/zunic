#!/usr/bin/env python3
"""Common summary schema and reporter for every Rust comparison."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import statistics

from benchmark_contract import output_report, parse_dump, check_rows, compare_operations, fields
from benchmark_table import Ratio, report as terminal_tables

SCHEMA = "zunic-rust-benchmark/v1"


def _nested(results):
    if not results or all(isinstance(value, dict) and "median_ns" not in value for value in results.values()):
        return results
    nested = {}
    for key, row in results.items():
        case, operation = key.split("/", 1)
        nested.setdefault(case, {})[operation] = row
    return nested


def create_summary(*, suite, title, label, pairs, comparisons, peers, contract,
                   outputs, notes, environment, provenance, operation_outputs=None):
    normalized_pairs = []
    for pair in pairs:
        normalized_pairs.append({
            "name": pair["name"],
            "order": list(pair.get("order", ("zunic", "rust"))),
            "results": {peer: _nested(pair[peer]) for peer in ("zunic", "rust")},
        })
    summary = {
        "schema": SCHEMA,
        "suite": suite,
        "title": title,
        "label": label,
        "pair_count": len(normalized_pairs),
        "cases": list(normalized_pairs[0]["results"]["zunic"]) if normalized_pairs else [],
        "comparisons": comparisons,
        "peers": peers,
        "contract": contract,
        "pairs": normalized_pairs,
        "outputs": outputs,
        "notes": notes,
        "environment": environment,
        "provenance": provenance,
    }
    if operation_outputs is not None:
        summary["operation_outputs"] = operation_outputs
    validate_summary(summary)
    return summary


def validate_summary(summary):
    if summary.get("schema") != SCHEMA:
        raise ValueError(f"unsupported summary schema: {summary.get('schema')!r}")
    cases = summary.get("cases", [])
    comparisons = summary.get("comparisons", [])
    pairs = summary.get("pairs", [])
    if not cases or not comparisons or len(pairs) != summary.get("pair_count"):
        raise ValueError("incomplete benchmark summary")
    for pair in pairs:
        if set(pair.get("results", {})) != {"zunic", "rust"}:
            raise ValueError(f"{pair.get('name', '?')}: missing peer results")
        for comparison in comparisons:
            for case in cases:
                for peer in ("zunic", "rust"):
                    operation = comparison[peer]
                    row = pair["results"].get(peer, {}).get(case, {}).get(operation)
                    if row is None:
                        raise ValueError(f"{pair['name']}/{case}/{peer}/{operation}: missing result")
                    required = {"bytes", "units", "iterations", "median_ns", "mad_ns", "checksum", "samples_ns"}
                    if not required <= row.keys() or len(row["samples_ns"]) != 15:
                        raise ValueError(f"{pair['name']}/{case}/{peer}/{operation}: invalid result")
    if "operation_outputs" in summary:
        evidence = summary["operation_outputs"]
        if set(evidence) != {comparison["id"] for comparison in comparisons}:
            raise ValueError("operation output comparisons do not match timing comparisons")
        for comparison in comparisons:
            rows = evidence[comparison["id"]]
            if set(rows) != set(cases):
                raise ValueError("incomplete operation output cases")
            for case, output in rows.items():
                if type(output.get("equal")) is not bool:
                    raise ValueError("operation output equality must be boolean")
                for peer in ("zunic", "rust"):
                    for pair in pairs:
                        units = pair["results"][peer][case][comparison[peer]]["units"]
                        if output.get(peer + "_count") != units:
                            raise ValueError("operation output count differs from timed units")
    return summary


def output_rows(summary, comparison):
    if "operation_outputs" in summary:
        return summary["operation_outputs"][comparison["id"]]
    # A legacy suite-level flag cannot establish equality for a viewport,
    # filtered output, or individual normalization form.
    return {case: {"equal": None} for case in summary["cases"]}


def output_status(row):
    return {True: "same", False: "diff", None: "unverified"}[row.get("equal")]


def output_notes(summary):
    return [comparison["label"] + ": " + output_report(output_rows(summary, comparison))
            for comparison in summary["comparisons"]]


def load_summary(path):
    """Recover operation evidence from legacy dumps without changing archives."""
    path = Path(path)
    summary = json.loads(path.read_text())
    validate_summary(summary)
    suite = summary["suite"]
    if "operation_outputs" not in summary and suite in ("wrap", "words", "strip_ansi", "linebreak"):
        suffix = "-streams-before.txt" if suite == "linebreak" else "-before.dump"
        dumps = {peer: path.parent / (peer + suffix) for peer in ("zunic", "rust")}
        texts = path.parent / "texts"
        if all(file.exists() for file in dumps.values()) and (texts.is_dir() or suite == "linebreak"):
            snapshots = {file.stem: file.read_bytes() for file in texts.glob("*.txt")}
            if not snapshots and suite == "linebreak":
                # Linebreak archives include input bytes in the stream dumps.
                snapshots = {row["case"]: bytes.fromhex(row["input"])
                             for line in dumps["zunic"].read_text().splitlines()
                             if "input" in (row := fields(line))}
                if set(snapshots) != set(summary["cases"]):
                    raise ValueError("incomplete archived linebreak inputs")
            outputs = {peer: parse_dump(file.read_text(), snapshots, suite) for peer, file in dumps.items()}
            for pair in summary["pairs"]:
                for peer in ("zunic", "rust"):
                    check_rows(pair["results"][peer], outputs[peer], suite)
                    for case, operations in pair["results"][peer].items():
                        if any(row["bytes"] != len(snapshots[case]) for row in operations.values()):
                            raise ValueError("archived input size differs from timed input")
            summary["operation_outputs"] = compare_operations(outputs, suite, summary["comparisons"], summary["cases"])
            validate_summary(summary)
    if "operation_outputs" not in summary and suite == "normalize":
        dumps = {peer: path.parent / f"{peer}-before.dump" for peer in ("zunic", "rust")}
        texts = path.parent / "texts"
        if texts.is_dir() and all(file.exists() for file in dumps.values()):
            outputs = {}
            for peer, file in dumps.items():
                records = {}
                for line in file.read_text().splitlines():
                    data = fields(line)
                    key = (data["case"], data["form"])
                    if key in records:
                        raise ValueError("duplicate archived normalization output")
                    source = (texts / (data["case"] + ".txt")).read_bytes()
                    if bytes.fromhex(data["input"]) != source:
                        raise ValueError("archived normalization input mismatch")
                    value = bytes.fromhex(data["hex"]).decode("utf-8")
                    for pair in summary["pairs"]:
                        row = pair["results"][peer][key[0]][key[1]]
                        if (row["bytes"] != len(source) or row["units"] != len(value) or
                                row["checksum"] != sum(map(ord, value)) % (1 << 64)):
                            raise ValueError("archived normalization output differs from timed result")
                    records[key] = value
                expected = {(case, comparison[peer]) for case in summary["cases"]
                            for comparison in summary["comparisons"]}
                if set(records) != expected:
                    raise ValueError("incomplete archived normalization outputs")
                outputs[peer] = records
            summary["operation_outputs"] = {
                comparison["id"]: {case: {
                    "equal": outputs["zunic"][(case, comparison["zunic"])] == outputs["rust"][(case, comparison["rust"])],
                    "zunic_count": len(outputs["zunic"][(case, comparison["zunic"])]),
                    "rust_count": len(outputs["rust"][(case, comparison["rust"])]),
                } for case in summary["cases"]} for comparison in summary["comparisons"]}
            validate_summary(summary)
    return summary


def median_row(summary, peer, case, operation):
    rows = [pair["results"][peer][case][operation] for pair in summary["pairs"]]
    return {
        "median_ns": statistics.median(row["median_ns"] for row in rows),
        "units": rows[0]["units"],
    }


def terminal_report(summary):
    validate_summary(summary)
    sections = []
    for comparison in summary["comparisons"]:
        rows = []
        for case in summary["cases"]:
            z = median_row(summary, "zunic", case, comparison["zunic"])
            r = median_row(summary, "rust", case, comparison["rust"])
            output = output_rows(summary, comparison)[case]
            rows.append([case, f"{z['median_ns'] / 1000:.3f}", f"{r['median_ns'] / 1000:.3f}",
                         Ratio(r["median_ns"] / z["median_ns"]), f"{z['units']}/{r['units']}",
                         output_status(output)])
        sections.append((comparison["label"],
                         ["Corpus", "Zunic µs", "Rust µs", "Rust/Zunic", "Units Z/R", "Output"], rows))
    peer_note = (f"Unicode: Zunic {summary['peers']['zunic']['unicode']}; "
                 f"{summary['peers']['rust']['name']} {summary['peers']['rust']['unicode']}.")
    return terminal_tables(summary["title"], sections,
                           [peer_note, *output_notes(summary), *summary.get("notes", [])])


def markdown_report(summary):
    validate_summary(summary)
    lines = [f"# {summary['title']}", "", f"Label: `{summary['label']}`. "
             f"Sequential alternating pairs: {summary['pair_count']}.", "",
             f"Unicode: Zunic {summary['peers']['zunic']['unicode']}; "
             f"{summary['peers']['rust']['name']} {summary['peers']['rust']['unicode']}.", ""]
    for comparison in summary["comparisons"]:
        lines.extend([f"## {comparison['label']}", "",
                      "| Corpus | Zunic µs | Rust µs | Rust/Zunic | Units Z/R | Output |",
                      "| --- | ---: | ---: | ---: | ---: | :---: |"])
        for case in summary["cases"]:
            z = median_row(summary, "zunic", case, comparison["zunic"])
            r = median_row(summary, "rust", case, comparison["rust"])
            status = output_status(output_rows(summary, comparison)[case])
            lines.append(f"| {case} | {z['median_ns'] / 1000:.3f} | {r['median_ns'] / 1000:.3f} | "
                         f"{r['median_ns'] / z['median_ns']:.2f}× | {z['units']}/{r['units']} | "
                         f"{status} |")
        lines.append("")
    lines.extend([*output_notes(summary), "",
                  f"Input: {summary['contract']['input']}. Consumption: {summary['contract']['consumption']}.",
                  *summary.get("notes", []), ""])
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("summary", type=Path)
    parser.add_argument("--format", choices=("terminal", "markdown"), default="terminal")
    args = parser.parse_args()
    summary = load_summary(args.summary)
    print(terminal_report(summary) if args.format == "terminal" else markdown_report(summary))


if __name__ == "__main__":
    main()
