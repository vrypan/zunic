//! Default Unicode 16.0 line-break boundaries (UAX #14 revision 53).
//!
//! This iterator reports the default, locale-independent opportunities only.
//! It does not select lines by terminal width, tailor rules with CLDR data, or
//! perform dictionary segmentation for complex South East Asian text. SA
//! letters therefore resolve to AL; SA marks resolve to CM as required by LB1.
const properties = @import("properties.zig");
const scalar = @import("scalar.zig");

pub const Opportunity = enum { prohibited, allowed, mandatory };
pub const Boundary = struct { offset: usize, opportunity: Opportunity };

const Class = enum {
    ai,
    ak,
    al,
    ap,
    as,
    b2,
    ba,
    bb,
    bk,
    cb,
    cj,
    cl,
    cm,
    cp,
    cr,
    eb,
    em,
    ex,
    gl,
    h2,
    h3,
    hl,
    hy,
    id,
    in,
    is,
    jl,
    jt,
    jv,
    lf,
    nl,
    ns,
    nu,
    op,
    po,
    pr,
    qu,
    ri,
    sa,
    sg,
    sp,
    sy,
    vf,
    vi,
    wj,
    xx,
    zw,
    zwj,
};

const Token = struct {
    scalar: scalar.Token,
    raw: Class,
};

pub const Iterator = struct {
    bytes: []const u8,
    pos: usize = 0,
    initialized: bool = false,
    finished: bool = false,
    previous: Class = .al,
    previous_raw: Class = .al,
    previous_base_cp: u21 = 0,
    before_previous: Class = .al,
    before_previous_cp: u21 = 0,
    previous_at_sot: bool = false,
    zw_sp: bool = false,
    op_sp: bool = false,
    qu_pi_sp: bool = false,
    cl_cp_sp: bool = false,
    b2_sp: bool = false,
    hl_ba_hy: bool = false,
    word_initial_hy: bool = false,
    po_pr_before_op: bool = false,
    num_is_sy: bool = false,
    number_cl_cp: bool = false,
    aksara_vi: bool = false,
    ri_count: usize = 0,
    next_token: ?Token = null,

    pub fn next(self: *Iterator) ?Boundary {
        if (self.finished) return null;
        if (!self.initialized) {
            self.initialized = true;
            if (self.bytes.len == 0) {
                self.finished = true;
                return .{ .offset = 0, .opportunity = .mandatory };
            }
            self.consumeFirst();
            return .{ .offset = 0, .opportunity = .prohibited };
        }
        if (self.pos == self.bytes.len) {
            self.finished = true;
            return .{ .offset = self.pos, .opportunity = .mandatory };
        }

        const offset = self.pos;
        const token = self.takeToken();
        const raw = token.raw;
        const cp = token.scalar.codepoint orelse 0;
        const current = resolve(raw, cp, self.previous, self.previous_raw);
        const following = self.peekToken();
        const next_raw = following.raw;
        const next_cp = following.scalar.codepoint orelse 0;
        const opportunity = breakBefore(self, raw, current, cp, next_raw, next_cp, following.scalar.end != following.scalar.start);
        self.consume(raw, current, cp);
        return .{ .offset = offset, .opportunity = opportunity };
    }

    fn consumeFirst(self: *Iterator) void {
        const token = self.takeToken();
        const raw = token.raw;
        const cp = token.scalar.codepoint orelse 0;
        const current = resolve(raw, cp, .al, .bk);
        self.previous = current;
        self.previous_raw = raw;
        self.previous_base_cp = cp;
        self.previous_at_sot = true;
        self.updateState(raw, current, cp);
        self.qu_pi_sp = current == .qu and properties.isQuPi(cp);
        self.word_initial_hy = current == .hy or cp == 0x2010;
    }

    fn takeToken(self: *Iterator) Token {
        const token = self.next_token orelse self.decodeAt(self.pos);
        self.next_token = null;
        self.pos = token.scalar.end;
        return token;
    }

    fn peekToken(self: *Iterator) Token {
        if (self.next_token == null) self.next_token = self.decodeAt(self.pos);
        return self.next_token.?;
    }

    fn decodeAt(self: *const Iterator, offset: usize) Token {
        const token = scalar.at(self.bytes, offset);
        return .{ .scalar = token, .raw = rawClass(token.codepoint) };
    }

    fn consume(self: *Iterator, raw: Class, current: Class, cp: u21) void {
        self.before_previous = self.previous;
        self.before_previous_cp = self.previous_base_cp;
        self.previous = current;
        self.previous_raw = raw;
        if (raw != .cm and raw != .zwj) self.previous_base_cp = cp;
        if (raw != .cm and raw != .zwj) self.previous_at_sot = false;
        self.updateState(raw, current, cp);
    }

    fn updateState(self: *Iterator, raw: Class, current: Class, cp: u21) void {
        const was_op_sp = self.op_sp;
        const was_qu_pi_sp = self.qu_pi_sp;
        const was_cl_cp_sp = self.cl_cp_sp;
        const was_b2_sp = self.b2_sp;
        const was_num_is_sy = self.num_is_sy;
        const was_word_initial_hy = self.word_initial_hy;
        const was_aksara_vi = self.aksara_vi;
        self.zw_sp = raw == .zw or (raw == .sp and self.zw_sp);
        self.op_sp = current == .op or (raw == .sp and was_op_sp);
        self.qu_pi_sp = if (raw == .cm or raw == .zwj) was_qu_pi_sp else (current == .qu and properties.isQuPi(cp) and isLb15aStart(self.before_previous)) or (raw == .sp and was_qu_pi_sp);
        self.cl_cp_sp = (current == .cl or current == .cp) or (raw == .sp and was_cl_cp_sp);
        self.b2_sp = current == .b2 or (raw == .sp and was_b2_sp);
        self.hl_ba_hy = self.before_previous == .hl and (current == .hy or (current == .ba and !properties.isEastAsianWide(cp)));
        self.word_initial_hy = if (raw == .cm or raw == .zwj) was_word_initial_hy else (current == .hy or cp == 0x2010) and isWordInitialBreakContext(self.before_previous);
        self.po_pr_before_op = current == .op and (self.before_previous == .po or self.before_previous == .pr);
        self.number_cl_cp = (current == .cl or current == .cp) and was_num_is_sy;
        self.num_is_sy = current == .nu or ((current == .is or current == .sy) and was_num_is_sy);
        self.aksara_vi = if (raw == .cm or raw == .zwj) was_aksara_vi else current == .vi and isAksara(self.before_previous, self.before_previous_cp);
        if (raw == .cm or raw == .zwj) {
            // LB9 ignores combining marks while counting the RI run for LB30a.
        } else if (current == .ri) {
            self.ri_count += 1;
        } else {
            self.ri_count = 0;
        }
    }
};

pub fn iterator(bytes: []const u8) Iterator {
    return .{ .bytes = bytes };
}

// LB4-LB31, after LB1 resolution. Earlier rules take precedence.
fn breakBefore(it: *const Iterator, raw: Class, current: Class, cp: u21, next_raw: Class, next_cp: u21, has_next: bool) Opportunity {
    // LB5 and LB6: preserve CRLF, and force boundaries around hard breaks.
    if (it.previous_raw == .cr and raw == .lf) return .prohibited;
    if (isHard(it.previous_raw)) return .allowed;
    if (isHard(raw)) return .prohibited;

    // LB7-LB10: ZW and spaces, ZWJ, and combining sequences.
    if (raw == .sp or raw == .zw) return .prohibited;
    if (it.zw_sp) return .allowed; // LB8: ZW SP* ÷
    if (it.previous_raw == .zwj) return .prohibited; // LB8a
    if ((raw == .cm or raw == .zwj) and it.previous != .sp and it.previous_raw != .zw) return .prohibited; // LB9

    // LB11-LB17: non-breaking characters and punctuation with SP* context.
    if (it.previous == .wj or current == .wj) return .prohibited;
    // LB12/LB12a: GL only permits a preceding SP, BA, or HY.
    if (it.previous == .gl) return .prohibited;
    if (current == .gl and it.previous != .sp and it.previous != .ba and it.previous != .hy) return .prohibited;
    if (it.previous == .sp and current == .is and next_raw == .nu) return .allowed; // LB15c
    if (isClosing(current)) return .prohibited;
    if (it.op_sp) return .prohibited;
    if (it.qu_pi_sp) return .prohibited; // LB15a
    if (current == .qu and properties.isQuPf(cp) and (!has_next or isLb15bFollower(next_raw))) return .prohibited; // LB15b
    if (current == .is) return .prohibited; // LB15d
    if (it.cl_cp_sp and current == .ns) return .prohibited;
    if (it.b2_sp and current == .b2) return .prohibited;
    if (it.previous == .sp) return .allowed; // LB18
    if (current == .qu and !properties.isQuPi(cp)) return .prohibited; // LB19
    if (current == .qu and (!properties.isEastAsianWide(it.previous_base_cp) or !has_next or !properties.isEastAsianWide(next_cp))) return .prohibited; // LB19a
    if (it.previous == .qu and it.previous_at_sot) return .prohibited; // LB19a
    if (it.previous == .qu and !properties.isEastAsianWide(it.before_previous_cp)) return .prohibited; // LB19a
    if (it.previous == .qu and !properties.isEastAsianWide(cp)) return .prohibited; // LB19a
    if (it.previous == .qu and !properties.isQuPf(it.previous_base_cp)) return .prohibited;
    if (it.previous == .cb or current == .cb) return .allowed;
    if (current == .ba or current == .hy or current == .ns or it.previous == .bb) return .prohibited;
    if (it.hl_ba_hy and current != .hl) return .prohibited; // LB21a
    if (it.word_initial_hy and current == .al) return .prohibited; // LB20a
    if (it.previous == .sy and current == .hl) return .prohibited; // LB21b

    // LB22-LB25: inseparables, letters, prefixes/suffixes, and numbers.
    if (current == .in) return .prohibited;
    if ((isAlphabetic(it.previous) and current == .nu) or (it.previous == .nu and isAlphabetic(current))) return .prohibited;
    if ((it.previous == .pr and isIdeographicOrEmoji(current)) or (isIdeographicOrEmoji(it.previous) and current == .po)) return .prohibited;
    if ((isPrefixOrPostfix(it.previous) and isAlphabetic(current)) or (isAlphabetic(it.previous) and isPrefixOrPostfix(current))) return .prohibited;
    if (it.num_is_sy and (current == .po or current == .pr or current == .nu)) return .prohibited;
    if (it.number_cl_cp and isPrefixOrPostfix(current)) return .prohibited;
    if ((it.previous == .po or it.previous == .pr) and current == .nu) return .prohibited;
    if (it.previous == .hy and current == .nu) return .prohibited;
    if (it.previous == .is and current == .nu) return .prohibited;
    if ((it.previous == .po or it.previous == .pr) and current == .op and (next_raw == .nu or nextAfterCurrentIsNu(it))) return .prohibited;
    if (it.po_pr_before_op and (current == .nu or (current == .is and next_raw == .nu))) return .prohibited;

    // LB26-LB30b: Hangul, Brahmic syllables, alphabetics, and emoji.
    if (hangulPair(it.previous, current)) return .prohibited;
    if (isHangul(it.previous) and (current == .in or current == .po)) return .prohibited;
    if (it.previous == .pr and isHangul(current)) return .prohibited;
    if (isAlphabetic(it.previous) and isAlphabetic(current)) return .prohibited;
    if (it.previous == .ap and isAksara(current, cp)) return .prohibited;
    if (isAksara(it.previous, it.previous_base_cp) and (current == .vf or current == .vi)) return .prohibited;
    if (it.aksara_vi and (current == .ak or cp == 0x25CC)) return .prohibited;
    if (isAksara(it.previous, it.previous_base_cp) and isAksara(current, cp) and next_raw == .vf) return .prohibited;
    if (it.previous == .is and isAlphabetic(current)) return .prohibited;
    if ((isAlphabetic(it.previous) or it.previous == .nu) and current == .op and properties.isOp30(cp)) return .prohibited;
    if (it.previous == .cp and properties.isCp30(it.previous_base_cp) and (isAlphabetic(current) or current == .nu)) return .prohibited;
    if (it.previous == .ri and current == .ri and it.ri_count % 2 == 1) return .prohibited;
    if ((it.previous == .eb or properties.isExtendedPictographicCn(it.previous_base_cp)) and current == .em) return .prohibited;

    return .allowed; // LB31
}

fn rawClass(maybe_cp: ?u21) Class {
    const cp = maybe_cp orelse return .al;
    return @enumFromInt(@intFromEnum(properties.lineBreak(cp)));
}

// LB1. The fallback for malformed UTF-8 is AL in rawClass.
fn resolve(raw: Class, cp: u21, previous: Class, previous_raw: Class) Class {
    return switch (raw) {
        .ai, .sg, .xx => .al,
        .cj => .ns,
        .sa => if (properties.isSaMnMc(cp)) .cm else .al,
        .cm, .zwj => if (isHard(previous_raw) or previous == .sp or previous_raw == .zw) .al else previous,
        else => raw,
    };
}

fn isHard(c: Class) bool {
    return c == .bk or c == .cr or c == .lf or c == .nl;
}
fn isClosing(c: Class) bool {
    return c == .cl or c == .cp or c == .ex or c == .is or c == .sy;
}
fn isAlphabetic(c: Class) bool {
    return c == .al or c == .hl;
}
fn isPrefixOrPostfix(c: Class) bool {
    return c == .pr or c == .po;
}
fn isIdeographicOrEmoji(c: Class) bool {
    return c == .id or c == .eb or c == .em;
}
fn isHangul(c: Class) bool {
    return c == .jl or c == .jv or c == .jt or c == .h2 or c == .h3;
}
fn isAksara(c: Class, cp: u21) bool {
    return c == .ak or c == .as or cp == 0x25CC;
}
fn isLb15aStart(c: Class) bool {
    return isHard(c) or c == .op or c == .qu or c == .gl or c == .sp or c == .zw;
}
fn isLb15bFollower(c: Class) bool {
    return c == .sp or c == .gl or c == .wj or c == .cl or c == .qu or c == .cp or c == .ex or c == .is or c == .sy or isHard(c) or c == .zw;
}
fn isWordInitialBreakContext(c: Class) bool {
    return isHard(c) or c == .sp or c == .zw or c == .cb or c == .gl;
}
fn nextAfterCurrentIsNu(it: *const Iterator) bool {
    const next = it.next_token orelse it.decodeAt(it.pos);
    if (next.raw != .is) return false;
    return it.decodeAt(next.scalar.end).raw == .nu;
}
fn hangulPair(left: Class, right: Class) bool {
    if (left == .jl) return right == .jl or right == .jv or right == .h2 or right == .h3;
    if (left == .jv or left == .h2) return right == .jv or right == .jt;
    return (left == .jt or left == .h3) and right == .jt;
}
