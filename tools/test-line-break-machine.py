#!/usr/bin/env python3
"""Check reproducibility and Unicode 17 semantic/compiler invariants."""
from pathlib import Path
import subprocess
import sys

def main():
    tools = Path(__file__).resolve().parent
    subprocess.run([sys.executable, str(tools / "generate-line-break-machine.py"), "--check"], check=True)
    subprocess.run([sys.executable, str(tools / "test-line-break-semantics.py")], check=True)

if __name__ == "__main__":
    main()
