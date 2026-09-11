#!/usr/bin/env python3
"""Time zunic's per-script operations over the UDHR corpora.

    python3 src/tools/fetch-udhr.py       # once, to get the text
    python3 src/tools/benchmark-udhr.py
    python3 src/tools/benchmark-udhr.py --against HEAD   # compare with a ref

Advisory, not a gate. `src/tools/benchmark-history.py` remains the harness for
tracked measurements; this answers a different question, namely how an
operation behaves across writing systems on the *same* document.

Why that matters. zunic's own corpora are synthesized from unigram frequency
tables (see generate-corpora.py), which reproduces how often a code point
occurs but not how code points are arranged. Anything sensitive to structure
rather than distribution is measured wrongly by them. A concrete case: in real
Russian, ASCII appears as single bytes between words -- median run length 1 --
while the synthesized corpus scatters it, and a width fast path keyed on ASCII
run length looked 8-17% slower there than it actually was.

Timing is min-of-N, since the floor is the least noisy statistic on a busy
laptop. Treat differences under about 5% as unmeasured; see
private/benchmarks/ for how noisy this gets.
"""

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CORPORA = ROOT / "data" / "udhr"
REPO = ROOT.parent

OPERATIONS = {
    "width": "zunic.text(c.text).width()",
    "graphemes": "blk: { var n: usize = 0; var it = zunic.text(c.text).graphemes().iterator(); while (it.next()) |_| n += 1; break :blk n; }",
    "words": "blk: { var n: usize = 0; var it = zunic.text(c.text).wordBounds().iterator(); while (it.next()) |_| n += 1; break :blk n; }",
    "wrap": "blk: { var n: usize = 0; var it = (zunic.text(c.text).wrap(.{ .max_columns = 80 }) catch unreachable).iterator(); while (it.next()) |_| n += 1; break :blk n; }",
    "nfc": "blk: { var n: usize = 0; var it = zunic.text(c.text).normalize(.nfc); while (it.next() catch null) |cp| n +%= cp; break :blk n; }",
}

PROBE = """const std = @import("std");
const zunic = @import("zunic");

const Case = struct {{ name: []const u8, text: []const u8 }};
const cases = [_]Case{{
{cases}
}};

pub fn main(init: std.process.Init) !void {{
    const io = init.io;
    var buf: [8192]u8 = undefined;
    var out = std.Io.File.stdout().writer(io, &buf);
    const w = &out.interface;
    for (cases) |c| {{
        var best: u64 = std.math.maxInt(u64);
        var sink: usize = 0;
        for (0..{rounds}) |_| {{
            const t0 = std.Io.Clock.Timestamp.now(io, .awake);
            for (0..{inner}) |_| sink +%= {expr};
            const ns: u64 = @intCast(t0.durationTo(std.Io.Clock.Timestamp.now(io, .awake)).raw.toNanoseconds());
            best = @min(best, ns);
        }}
        try w.print("{{s}}\\t{{d}}\\t{{d}}\\t{{d}}\\n", .{{ c.name, c.text.len, best, sink % 1000003 }});
    }}
    try w.flush();
}}
"""

MODULES = [
    ("tables", "src/tables/tables.zig", []),
    ("encoding", "src/encoding/encoding.zig", ["tables"]),
    ("segmentation", "src/segmentation/segmentation.zig", ["tables", "encoding"]),
    ("linebreak", "src/linebreak/linebreak.zig", ["tables", "encoding"]),
    ("normalization", "src/normalization/normalization.zig", ["tables", "encoding", "build_options"]),
    ("layout", "src/layout/layout.zig", ["tables", "encoding", "segmentation", "linebreak", "build_options"]),
]


def build_and_run(source_root: Path, operation: str, corpora: list[Path], work: Path, rounds: int, inner: int) -> dict:
    """Compile a probe against `source_root` and return {corpus: (bytes, ns)}."""
    for path in corpora:
        shutil.copy(path, work / path.name)
    cases = "\n".join(f'    .{{ .name = "{p.stem}", .text = @embedFile("{p.name}") }},' for p in corpora)
    (work / "probe.zig").write_text(PROBE.format(cases=cases, expr=OPERATIONS[operation], rounds=rounds, inner=inner))
    (work / "opts.zig").write_text(
        "pub const normalization_buffer_bytes: usize = 128;\n"
        "pub const wrap_fast_path = enum { off, scalar, auto, simd }.auto;\n"
    )

    command = ["zig", "build-exe", "-OReleaseFast", "-femit-bin=probe", "--dep", "zunic", "-Mroot=probe.zig"]
    # Older snapshots predate the shared types module; intermediate snapshots
    # also contain the now-removed ANSI terminal module.
    modules = list(MODULES)
    if (source_root / "src/types.zig").exists():
        modules.append(("types", "src/types.zig", []))
    if (source_root / "src/terminal/terminal.zig").exists():
        modules.append(("terminal", "src/terminal/terminal.zig", ["types", "encoding", "segmentation"]))
    for name, _, _ in modules:
        command += ["--dep", name]
    command += ["--dep", "build_options", f"-Mzunic={source_root}/src/root.zig", "-Mbuild_options=opts.zig"]
    for name, rel, deps in modules:
        for dep in deps:
            command += ["--dep", dep]
        command.append(f"-M{name}={source_root}/{rel}")

    subprocess.run(command, cwd=work, check=True, capture_output=True)
    output = subprocess.run(["./probe"], cwd=work, check=True, capture_output=True, text=True).stdout
    result = {}
    for line in output.splitlines():
        name, size, ns, _ = line.split("\t")
        result[name] = (int(size), int(ns))
    return result


def worktree(ref: str, work: Path) -> Path:
    """A detached checkout of `ref`, so the comparison shares no build cache."""
    target = work / "ref"
    subprocess.run(["git", "worktree", "add", "--detach", str(target), ref],
                   cwd=REPO, check=True, capture_output=True)
    return target


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--operation", "-o", default="width", choices=sorted(OPERATIONS), help="what to time")
    parser.add_argument("--against", metavar="REF", help="also measure this git ref and report the delta")
    parser.add_argument("--rounds", type=int, default=40, help="timed rounds; the minimum is reported")
    parser.add_argument("--inner", type=int, default=20, help="repetitions inside each round")
    parser.add_argument("--json", action="store_true", help="emit machine-readable output")
    args = parser.parse_args()

    corpora = sorted(CORPORA.glob("*.txt"))
    if not corpora:
        print(f"no corpora in {CORPORA.relative_to(REPO)}; run src/tools/fetch-udhr.py first", file=sys.stderr)
        return 2

    added_worktree = None
    try:
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            (work / "now").mkdir()
            now = build_and_run(REPO, args.operation, corpora, work / "now", args.rounds, args.inner)

            base = None
            if args.against:
                (work / "base").mkdir()
                added_worktree = worktree(args.against, work)
                base = build_and_run(added_worktree, args.operation, corpora, work / "base", args.rounds, args.inner)

            if args.json:
                print(json.dumps({"operation": args.operation, "now": now, "base": base}, indent=2))
                return 0

            print(f"operation: {args.operation}   corpora: {len(corpora)}   min of {args.rounds} rounds")
            header = f"\n  {'corpus':<16} {'bytes':>8} {'MiB/s':>9}"
            if base:
                header += f" {args.against + ' MiB/s':>16} {'change':>9}"
            print(header)
            for name in sorted(now):
                size, ns = now[name]
                rate = size * args.inner / 1048576 / (ns / 1e9)
                line = f"  {name:<16} {size:>8} {rate:>9.0f}"
                if base and name in base:
                    bsize, bns = base[name]
                    brate = bsize * args.inner / 1048576 / (bns / 1e9)
                    line += f" {brate:>16.0f} {(bns - ns) / bns * 100:>+8.1f}%"
                print(line)
            if base:
                print("\n  change is time saved: positive means the working tree is faster.")
        return 0
    finally:
        if added_worktree:
            subprocess.run(["git", "worktree", "remove", "--force", str(added_worktree)],
                           cwd=REPO, capture_output=True)


if __name__ == "__main__":
    sys.exit(main())
