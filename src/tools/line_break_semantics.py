"""Reachable semantic histories for the Unicode 16 line-break compiler.

Each edge here consumes an input and
produces a complete successor state. No Cartesian product of history flags is
constructed. Categories come from the checked-in fused Unicode records.
"""

from collections import deque
from dataclasses import dataclass
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
HARD = frozenset(("bk", "cr", "lf", "nl"))
MARK = frozenset(("cm", "zwj"))
QUOTE_START = HARD | {"op", "qu", "gl", "sp", "zw"}
WORD_START = HARD | {"sp", "zw", "cb", "gl"}


@dataclass(frozen=True, slots=True)
class Category:
    raw: str
    wide: bool = False
    pi: bool = False
    pf: bool = False
    op30: bool = False
    cp30: bool = False
    ep: bool = False
    sa_mark: bool = False
    hyphen: bool = False
    dotted: bool = False


def categories(points=()):
    """Return actual property combinations and one scalar witness for each.

    Property bits that affect another class only are removed. EAW is kept for
    every category because it can affect a neighboring quotation mark. Raw
    classes are retained here so lookahead and LB1 can be tested independently.
    """
    text = (ROOT / "properties.zig").read_text()
    classes = re.search(r"pub const LineBreak = enum\(u6\) \{(.*?)\n\};", text, re.S)
    names = re.findall(r"^    (\w+),$", classes[1], re.M)
    index = [int(x) for x in re.findall(r"\d+", re.search(
        r"pub const record_index = \[_\]u16\{(.*?)\n\};", text, re.S)[1])]
    data = [int(x, 16) for x in re.findall(r"0x[0-9a-fA-F]+", re.search(
        r"pub const record_data = \[_\]u32\{(.*?)\n\};", text, re.S)[1])]
    shift = int(re.search(r"pub const record_block_shift = (\d+);", text)[1])
    layout = re.search(r"pub const Record = packed struct\(u32\) \{(.*?)\n\};", text, re.S)[1]
    fields, offset = {}, 0
    for name, kind in re.findall(r"\s*(\w+): (\w+)(?: = [^,]+)?,", layout):
        bits = {"bool": 1, "GraphemeClass": 4, "IndicConjunctBreak": 2, "LineBreak": 6}.get(kind)
        if bits is None:
            bits = int(kind[1:])
        fields[name] = (offset, (1 << bits) - 1)
        offset += bits
    assert offset == 32

    cache, witnesses, selected = {}, {}, {}
    points = set(points)
    for cp in range(0x110000):
        if 0xD800 <= cp <= 0xDFFF:
            continue
        record = data[(index[cp >> shift] << shift) | (cp & ((1 << shift) - 1))]
        key = (record, cp == 0x2010, cp == 0x25CC)
        category = cache.get(key)
        if category is None:
            def value(name):
                bit, mask = fields[name]
                return (record >> bit) & mask
            raw = names[value("line_break")]
            category = Category(
                raw, bool(value("east_asian_wide")),
                raw == "qu" and bool(value("lb_qu_pi")),
                raw == "qu" and bool(value("lb_qu_pf")),
                raw == "op" and bool(value("lb_op30")),
                raw == "cp" and bool(value("lb_cp30")),
                bool(value("ep_cn")), raw == "sa" and bool(value("lb_sa_mn_mc")),
                cp == 0x2010, cp == 0x25CC,
            )
            cache[key] = category
        witnesses.setdefault(category, cp)
        if cp in points:
            selected[cp] = category
    return tuple(witnesses), tuple(witnesses.values()), selected


@dataclass(frozen=True, slots=True)
class History:
    previous: str = "al"
    raw: str = "bk"
    wide: bool = False
    pf: bool = False
    cp30: bool = False
    ep: bool = False
    dotted: bool = False
    before_wide: bool = False
    at_sot: bool = False
    zw_sp: bool = False
    op_sp: bool = False
    qu_pi_sp: bool = False
    cl_cp_sp: bool = False
    b2_sp: bool = False
    hl_hy: bool = False
    initial_hy: bool = False
    prefix_op: bool = False
    number: bool = False
    number_close: bool = False
    aksara_vi: bool = False
    ri_odd: bool = False


def resolve(state, category):
    raw = category.raw
    if raw in {"ai", "sg", "xx"}:
        return "al"
    if raw == "cj":
        return "ns"
    if raw == "sa":
        return "cm" if category.sa_mark else "al"
    if raw in MARK:
        return "al" if state.raw in HARD or state.previous == "sp" or state.raw == "zw" else state.previous
    return raw


def consume(state, category, *, first=False):
    """Canonical future-relevant history after exactly one scalar.

    before_previous class is not stored: updates use the outgoing previous
    class, and decisions only observe before_previous EAW when previous is QU.
    Base predicates retain the reference's raw CM/ZWJ lifetime.
    """
    p, raw = state.previous, category.raw
    c = resolve(state, category)
    mark = raw in MARK
    wide = state.wide if mark and not first else category.wide
    pf = state.pf if mark and not first else category.pf
    cp30 = state.cp30 if mark and not first else category.cp30
    ep = state.ep if mark and not first else category.ep
    dotted = state.dotted if mark and not first else category.dotted
    return History(
        previous=c, raw=raw, wide=wide, pf=pf, cp30=cp30, ep=ep, dotted=dotted,
        before_wide=state.wide if c == "qu" else False,
        at_sot=(first or (mark and state.at_sot)) if c == "qu" else False,
        zw_sp=raw == "zw" or (raw == "sp" and state.zw_sp),
        op_sp=c == "op" or (raw == "sp" and state.op_sp),
        qu_pi_sp=(c == "qu" and category.pi) if first else (
            state.qu_pi_sp if mark else
            (c == "qu" and category.pi and p in QUOTE_START) or (raw == "sp" and state.qu_pi_sp)),
        cl_cp_sp=c in {"cl", "cp"} or (raw == "sp" and state.cl_cp_sp),
        b2_sp=c == "b2" or (raw == "sp" and state.b2_sp),
        hl_hy=p == "hl" and (c == "hy" or (c == "ba" and not category.wide)),
        initial_hy=(c == "hy" or category.hyphen) if first else (
            state.initial_hy if mark else (c == "hy" or category.hyphen) and p in WORD_START),
        prefix_op=c == "op" and p in {"po", "pr"},
        number=c == "nu" or (c in {"is", "sy"} and state.number),
        number_close=c in {"cl", "cp"} and state.number,
        aksara_vi=state.aksara_vi if mark else c == "vi" and (p in {"ak", "as"} or state.dotted),
        ri_odd=state.ri_odd if mark else (not state.ri_odd if c == "ri" else False),
    )


def reachable(inputs):
    """BFS closure, with complete successor rows and shortest witnesses."""
    states = [None]  # SOT is explicit; it is never a consumed History.
    ids = {None: 0}
    rows, witnesses = [], [()]
    queue = deque([0])
    while queue:
        index = queue.popleft()
        row = []
        for ci, category in enumerate(inputs):
            successor = consume(states[index] or History(), category, first=index == 0)
            if successor not in ids:
                ids[successor] = len(states)
                states.append(successor)
                witnesses.append(witnesses[index] + (ci,))
                queue.append(ids[successor])
            row.append(ids[successor])
        rows.append(tuple(row))
    return states, rows, witnesses


def decision(state, category, following=None, second_nu=False):
    """Ordered Unicode 16 decisions, evaluated only by the offline compiler.

    0/1/2 denote prohibited/allowed/mandatory. Lookahead is reduced to the
    finite observable predicates; it never participates in state advancement.
    """
    if category is None:
        return 2
    if state is None:
        return 0
    p, raw, c = state.previous, category.raw, resolve(state, category)
    n = following.raw if following else "al"
    if state.raw == "cr" and raw == "lf":
        return 0
    if state.raw in HARD:
        return 2
    if raw in HARD or raw in {"sp", "zw"}:
        return 0
    if state.zw_sp:
        return 1
    if state.raw == "zwj":
        return 0
    if raw in MARK and p != "sp" and state.raw != "zw":
        return 0
    if p == "wj" or c == "wj" or p == "gl":
        return 0
    if c == "gl" and p not in {"sp", "ba", "hy"}:
        return 0
    if p == "sp" and c == "is" and n == "nu":
        return 1
    if c in {"cl", "cp", "ex", "is", "sy"} or state.op_sp or state.qu_pi_sp:
        return 0
    if c == "qu" and category.pf and (following is None or n in HARD | {"sp", "gl", "wj", "cl", "qu", "cp", "ex", "is", "sy", "zw"}):
        return 0
    if state.cl_cp_sp and c == "ns" or state.b2_sp and c == "b2":
        return 0
    if p == "sp":
        return 1
    if c == "qu" and (not category.pi or not state.wide or following is None or not following.wide):
        return 0
    if p == "qu" and (state.at_sot or not state.before_wide or not category.wide or not state.pf):
        return 0
    if p == "cb" or c == "cb":
        return 1
    if c in {"ba", "hy", "ns"} or p == "bb":
        return 0
    if state.hl_hy and c != "hl" or state.initial_hy and c == "al" or p == "sy" and c == "hl":
        return 0
    alpha, affix, ideo = {"al", "hl"}, {"pr", "po"}, {"id", "eb", "em"}
    if c == "in" or p in alpha and c == "nu" or p == "nu" and c in alpha:
        return 0
    if p == "pr" and c in ideo or p in ideo and c == "po":
        return 0
    if p in affix and c in alpha or p in alpha and c in affix:
        return 0
    if state.number and c in affix | {"nu"} or state.number_close and c in affix:
        return 0
    if p in affix | {"hy", "is"} and c == "nu":
        return 0
    if p in affix and c == "op" and (n == "nu" or n == "is" and second_nu):
        return 0
    if state.prefix_op and (c == "nu" or c == "is" and n == "nu"):
        return 0
    hangul = {"jl", "jv", "jt", "h2", "h3"}
    if p == "jl" and c in {"jl", "jv", "h2", "h3"} or p in {"jv", "h2"} and c in {"jv", "jt"} or p in {"jt", "h3"} and c == "jt":
        return 0
    if p in hangul and c in {"in", "po"} or p == "pr" and c in hangul:
        return 0
    if p in alpha and c in alpha:
        return 0
    aksara = c in {"ak", "as"} or category.dotted
    previous_aksara = p in {"ak", "as"} or state.dotted
    if p == "ap" and aksara or previous_aksara and c in {"vf", "vi"}:
        return 0
    if state.aksara_vi and (c == "ak" or category.dotted):
        return 0
    if previous_aksara and aksara and n == "vf":
        return 0
    if p == "is" and c in alpha:
        return 0
    if p in alpha | {"nu"} and c == "op" and category.op30:
        return 0
    if p == "cp" and state.cp30 and c in alpha | {"nu"}:
        return 0
    if p == "ri" and c == "ri" and state.ri_odd:
        return 0
    if (p == "eb" or state.ep) and c == "em":
        return 0
    return 1


def compile_machine(inputs):
    states, transitions, witnesses = reachable(inputs)
    # Lookahead observes raw class, EAW, EOT and second-following NU only.
    lookahead = tuple(dict.fromkeys((Category(x.raw, wide=x.wide), second)
                                   for x in inputs for second in (False, True))) + ((None, False),)
    outputs, signatures, signature_ids = [], [], {}
    for state in states:
        row = []
        for category in inputs:
            signature = bytes(decision(state, category, n, second) for n, second in lookahead)
            if signature not in signature_ids:
                signature_ids[signature] = len(signatures)
                signatures.append(signature)
            row.append(signature_ids[signature])
        outputs.append(tuple(row))

    # Moore refinement of Mealy output rows. Equal one-step outputs are only
    # the initial partition: successor partitions must also agree until stable.
    def partition(keys):
        groups = {}
        return [groups.setdefault(key, len(groups)) for key in keys]
    groups = partition(outputs)
    while True:
        refined = partition((outputs[i], tuple(groups[j] for j in row))
                            for i, row in enumerate(transitions))
        if refined == groups:
            break
        groups = refined
    representatives = [groups.index(g) for g in range(max(groups) + 1)]
    rows = [tuple((groups[j], outputs[i][c]) for c, j in enumerate(transitions[i]))
            for i in representatives]
    return states, witnesses, groups, rows, signatures, lookahead


def render():
    inputs, scalars, _ = categories()
    states, witnesses, groups, rows, signatures, lookahead = compile_machine(inputs)
    # Verify all generated decision patterns against the runtime's named
    # handlers. A new pattern must get an explicit handler, never a fallback.
    follower = HARD | {"sp", "gl", "wj", "cl", "qu", "cp", "ex", "is", "sy", "zw"}
    handlers = (
        lambda n, s: 0,
        lambda n, s: 1,
        lambda n, s: 2,
        lambda n, s: int(n is not None and n.raw == "nu"),
        lambda n, s: int(n is not None and n.raw not in follower),
        lambda n, s: int(not (n is not None and (n.raw == "nu" or n.raw == "is" and s))),
        lambda n, s: int(n is not None and n.wide),
        lambda n, s: int(n is None or n.raw != "vf"),
    )
    expected = [bytes(f(n, s) for n, s in lookahead) for f in handlers]
    assert signatures == expected, "unhandled semantic decision pattern"
    assert len(rows) <= 256
    source = (ROOT / "properties.zig").read_text()
    names = re.findall(r"^    (\w+),$", re.search(
        r"pub const LineBreak = enum\(u6\) \{(.*?)\n\};", source, re.S)[1], re.M)
    category_map = [255] * (len(names) * 8)
    for i, c in enumerate(inputs):
        # In the pinned data, these properties are disjoint within each raw
        # class. Prove injectivity before using this compact category map.
        special = c.pi or c.op30 or c.cp30 or c.ep or c.sa_mark or c.hyphen or c.dotted
        key = names.index(c.raw) * 8 + int(c.wide) + 2 * int(special) + 4 * int(c.pf)
        assert category_map[key] == 255, (c, "category-key collision")
        category_map[key] = i
    entries = [target | (action << 8) for row in rows for target, action in row]
    size = len(entries) * 2 + len(category_map)
    assert size <= 32 * 1024, size

    def array(name, kind, values):
        lines = [f"pub const {name} = [_]{kind}{{"]
        width = 4 if kind == "u16" else 2
        lines += ["    " + ", ".join(f"0x{v:0{width}x}" for v in values[i:i + 16]) + ","
                  for i in range(0, len(values), 16)]
        return "\n".join(lines + ["};\n"])
    return ("//! Generated by src/tools/generate-line-break-machine.py --write; do not edit.\n"
            f"// Unicode 16: {len(states)} reachable histories, {len(rows)} minimized states.\n"
            f"pub const category_count = {len(inputs)};\n"
            f"pub const state_count = {len(rows)};\n"
            f"pub const data_bytes = {size};\n"
            + array("category_map", "u8", category_map)
            + array("transitions", "u16", entries))


if __name__ == "__main__":
    output = ROOT / "line_break_machine_data.zig"
    rendered = render()
    if sys.argv[1:] == ["--write"]:
        output.write_text(rendered)
        print(f"wrote {output}")
    elif sys.argv[1:] == ["--check"]:
        assert output.read_text() == rendered, "semantic machine data is stale"
        print("semantic transition data: verified")
    else:
        raise SystemExit("usage: line_break_semantics.py --write|--check")
