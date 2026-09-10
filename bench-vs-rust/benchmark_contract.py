"""Shared, untimed verification for the bytes-to-results comparison harnesses."""
import re
import statistics

MASK = (1 << 64) - 1
CONTRACTS = {
    "strip_ansi": "bytes_fnv1",
    "normalize": "scalar_sum_v1",
    "words": "range_checksum_v1",
    "wrap": "line_bytes_fnv1",
    "linebreak": "offset_status_checksum_v1",
}


def fields(line):
    return dict(item.split("=", 1) for item in line.split() if "=" in item)


def parse_timing(text, *, suite, peer, cases, operations, expected_input="bytes"):
    """Parse the common v1 peer protocol into case/operation result rows."""
    lines = text.splitlines()
    headers = [fields(line) for line in lines if line.startswith("protocol=")]
    expected_header = {
        "protocol": "1",
        "suite": suite,
        "peer": peer,
        "samples": "15",
        "calibration_ms": "50",
        "input": expected_input,
        "consumption": CONTRACTS[suite],
    }
    if len(headers) != 1 or any(headers[0].get(key) != value for key, value in expected_header.items()):
        raise ValueError(f"incompatible benchmark header: expected {expected_header}, got {headers}")

    expected = {(case, operation) for case in cases for operation in operations}
    samples = {}
    results = {}
    for line in lines:
        row = fields(line)
        if not {"case", "op"} <= row.keys():
            continue
        key = (row["case"], row["op"])
        if key not in expected:
            raise ValueError(f"unexpected benchmark row: {key}")
        if "raw_samples=" in line:
            if key in samples:
                raise ValueError(f"duplicate samples: {key}")
            samples[key] = [int(value) for value in re.findall(r"\d+", line.split("raw_samples=", 1)[1])]
            continue
        if key in results:
            raise ValueError(f"duplicate result: {key}")
        values = samples.get(key, [])
        required = ("bytes", "units", "iterations", "ns", "mad", "checksum")
        if len(values) != 15 or any(name not in row for name in required):
            raise ValueError(f"missing or invalid result: {key}")
        median = int(statistics.median(values))
        mad = int(statistics.median(abs(value - median) for value in values))
        parsed = {
            "bytes": int(row["bytes"]),
            "units": int(row["units"]),
            "iterations": int(row["iterations"]),
            "median_ns": int(row["ns"]),
            "mad_ns": int(row["mad"]),
            "checksum": int(row["checksum"]),
            "samples_ns": values,
        }
        if parsed["median_ns"] != median or parsed["mad_ns"] != mad or not 1 <= parsed["iterations"] <= 1 << 20:
            raise ValueError(f"inconsistent result: {key}")
        results.setdefault(key[0], {})[key[1]] = parsed
    actual = {(case, operation) for case, rows in results.items() for operation in rows}
    if actual != expected:
        raise ValueError(f"incomplete results: missing={sorted(expected - actual)} extra={sorted(actual - expected)}")
    return results


def require_contract(text, kind):
    headers = [fields(line) for line in text.splitlines() if line.startswith("protocol=")]
    if len(headers) != 1 or headers[0].get("input") != "bytes" or headers[0].get("consumption") != CONTRACTS[kind]:
        raise ValueError("stale or incompatible binary: expected bytes input and " + CONTRACTS[kind])


def parse_dump(text, snapshots, kind):
    """Verify exact input identity, retain exact output records for comparison."""
    result = {}
    current = None
    byte_outputs = set()
    for line in text.splitlines():
        if line.startswith("case=") and " input=" in line:
            case, encoded = line.removeprefix("case=").split(" input=", 1)
            if case not in snapshots or case in result:
                raise ValueError(f"unexpected or duplicate corpus: {case}")
            if bytes.fromhex(encoded) != snapshots[case]:
                raise ValueError(f"{case}: binary input differs from corpus snapshot")
            result[case] = []
            current = case
        elif line.startswith("case=") and " stream=" in line:
            case, stream = line.removeprefix("case=").split(" stream=", 1)
            if case != current or kind != "linebreak":
                raise ValueError("unexpected stream header")
            result[case] = [(int(offset), {"allowed": 1, "mandatory": 2}[status])
                            for event in stream.split(",") if event
                            for offset, status in [event.split(":")]]
        elif line.startswith("S "):
            if current is None or kind != "words":
                raise ValueError("unexpected word record")
            _, start, end, flag = line.split()
            result[current].append((int(start), int(end), int(flag)))
        elif line.startswith("B "):
            if current is None or kind != "strip_ansi" or current in byte_outputs:
                raise ValueError("unexpected or duplicate byte output")
            result[current] = list(bytes.fromhex(line[2:]))
            byte_outputs.add(current)
        elif line.startswith("L "):
            if current is None or kind != "wrap":
                raise ValueError("unexpected line record")
            # Hex strings retain exact output bytes and are JSON serializable.
            result[current].append(bytes.fromhex(line[2:]).hex())
    if set(result) != set(snapshots):
        raise ValueError("incomplete dump")
    if kind == "strip_ansi" and byte_outputs != set(snapshots):
        raise ValueError("incomplete byte output")
    for case, records in result.items():
        if kind != "strip_ansi" and snapshots[case] and not records:
            raise ValueError(f"{case}: empty output for nonempty input")
        if kind == "words":
            cursor = 0
            for start, end, flag in records:
                if start != cursor or end <= start or end > len(snapshots[case]) or flag not in (0, 1):
                    raise ValueError(f"{case}: malformed word partition")
                snapshots[case][start:end].decode("utf-8")
                cursor = end
            if cursor != len(snapshots[case]):
                raise ValueError(f"{case}: incomplete word partition")
    return result


def signature(records, kind):
    checksum = 0xcbf29ce484222325 if kind in ("wrap", "strip_ansi") else 0
    for record in records:
        if kind == "strip_ansi":
            checksum = ((checksum ^ record) * 0x100000001b3) & MASK
        elif kind == "wrap":
            for byte in bytes.fromhex(record) + b"\xff":
                checksum = ((checksum ^ byte) * 0x100000001b3) & MASK
        else:
            for value in record[:2]:
                checksum = (checksum * 31 + value) & MASK
    return len(records), checksum


def operation_records(records, kind, operation):
    """Project verified output to exactly what this timed operation consumes."""
    if kind == "words":
        if operation in ("us_words", "zunic_words"):
            records = [record for record in records if record[2]]
        # Flags select word-like records but are not returned by the Rust
        # boundary operations or consumed by the common range contract.
        return [record[:2] for record in records]
    if kind == "wrap" and operation in ("zunic_first24", "textwrap_first_fit_take24"):
        return records[:24]
    return records


def compare_operations(outputs, kind, comparisons, cases=None):
    cases = list(outputs["zunic"]) if cases is None else cases
    result = {}
    for comparison in comparisons:
        rows = {}
        for case in cases:
            z = operation_records(outputs["zunic"][case], kind, comparison["zunic"])
            r = operation_records(outputs["rust"][case], kind, comparison["rust"])
            rows[case] = {"equal": z == r, "zunic_count": len(z), "rust_count": len(r)}
        result[comparison["id"]] = rows
    return result


def check_rows(rows, outputs, kind):
    for case, operations in rows.items():
        for op, row in operations.items():
            if kind == "linebreak" and op != "opportunities_only":
                continue  # Other rows are explicitly separate ablations.
            records = operation_records(outputs[case], kind, op)
            count, checksum = signature(records, kind)
            if row["units"] != count or row["checksum"] != checksum:
                raise ValueError(f"{case}/{op}: timed result differs from verified output")


def compare_outputs(outputs):
    return {case: {"equal": records == outputs["rust"][case],
                   "zunic_count": len(records), "rust_count": len(outputs["rust"][case])}
            for case, records in outputs["zunic"].items()}


def output_report(comparison):
    equal = [case for case, row in comparison.items() if row["equal"]]
    different = [case for case, row in comparison.items() if row["equal"] is False]
    unknown = [case for case, row in comparison.items() if row["equal"] is None]
    return ("Exact outputs matched: " + (", ".join(equal) or "none") + ". "
            "Exact outputs differed: " + (", ".join(different) or "none") + ". " +
            ("Operation output unverified: " + ", ".join(unknown) + ". " if unknown else "") +
            "Differences are reported without assuming a library bug or a Unicode-version cause.")
