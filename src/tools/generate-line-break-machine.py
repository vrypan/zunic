#!/usr/bin/env python3
"""Generate or verify the complete Unicode 16 semantic transition machine."""
import sys
from line_break_semantics import ROOT, render

def main():
    if sys.argv[1:] not in (["--write"], ["--check"]):
        raise SystemExit("usage: generate-line-break-machine.py --write|--check")
    output = ROOT / "tables/line_break_machine_data.zig"
    generated = render()
    if sys.argv[1] == "--write":
        output.write_text(generated)
        print(f"wrote {output}")
    else:
        assert output.read_text() == generated, "line-break machine data is stale"
        print("semantic transition data: verified")

if __name__ == "__main__":
    main()
