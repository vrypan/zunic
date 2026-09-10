#!/usr/bin/env python3
"""Byte-for-byte NFC/NFD comparison: unicode-normalization versus Zunic."""
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
CORPUS_DIR = HERE.parent / "texts"
ZUNIC_BIN = HERE / "zig-out/bin/zunic-normalize"
RUST_BIN = HERE / "target/release/unicode-normalization-zunic"

def dump(command):
    result = subprocess.run(command, capture_output=True, text=True)
    result.check_returncode()
    values = {}
    for line in result.stdout.splitlines():
        fields = dict(field.split("=", 1) for field in line.split() if "=" in field)
        values[(fields["case"], fields["form"])] = bytes.fromhex(fields["hex"])
    return values

for binary in (ZUNIC_BIN, RUST_BIN):
    if not binary.exists(): sys.exit(f"missing {binary}; build both release peers first")
zunic = dump([str(ZUNIC_BIN), "--dump"])
rust = dump([str(RUST_BIN), str(CORPUS_DIR), "--dump"])
if zunic.keys() != rust.keys(): sys.exit("different result sets")
failures = 0
for case, form in sorted(zunic):
    z, r = zunic[(case, form)], rust[(case, form)]
    if z == r: print(f"case={case} form={form} bytes={len(z)} status=identical")
    else:
        failures += 1
        print(f"case={case} form={form} status=differs zunic_bytes={len(z)} rust_bytes={len(r)}")
print(f"total: {len(zunic)} outputs (canonical and compatibility), {failures} byte differences")
raise SystemExit(bool(failures))
