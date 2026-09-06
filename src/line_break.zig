//! Default Unicode 16.0 line-break boundaries (UAX #14 revision 53).
//!
//! This iterator reports the default, locale-independent opportunities only.
//! It does not select lines by terminal width, tailor rules with CLDR data, or
//! perform dictionary segmentation for complex South East Asian text. SA
//! letters therefore resolve to AL; SA marks resolve to CM as required by LB1.
const properties = @import("properties.zig");
const scalar = @import("scalar.zig");
const semantic_machine = @import("line_break_machine.zig");
const std = @import("std");
const build_options = @import("build_options");

pub const Opportunity = semantic_machine.Opportunity;
pub const Boundary = struct { offset: usize, opportunity: Opportunity };

const Class = properties.LineBreak;

const Token = scalar.ClassifiedToken;

/// Internal UAX #14 transition state, separated from the byte iterator so a
/// fused scanner can drive it from an already-decoded token stream. The
/// protocol per scalar mirrors `Iterator.next`: resolve the raw class with
/// `resolveCurrent`, ask `opportunityBefore` for the boundary in front of the
/// scalar, then `consume` it. The first scalar of the text is consumed with
/// `first` instead and has no boundary decision.
/// The `WithRecord`/`WithRecords` variants accept retained scalar facts so the
/// scanner and iterator never repeat a property lookup to evaluate a rule.
/// Keep the original entry points for callers supplying raw classes and code
/// points. Cached base records follow the same LB9 lifetime as base code points.
pub const State = struct {
    previous: Class = .al,
    previous_raw: Class = .al,
    previous_base_cp: u21 = 0,
    before_previous: Class = .al,
    before_previous_cp: u21 = 0,
    previous_base_record: properties.Record = properties.record(0),
    before_previous_record: properties.Record = properties.record(0),
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

    pub fn first(raw: Class, cp: u21) State {
        return firstWithRecord(raw, cp, properties.record(cp));
    }

    pub fn firstWithRecord(raw: Class, cp: u21, r: properties.Record) State {
        var state = State{};
        const current = resolve(raw, r, .al, .bk);
        state.previous = current;
        state.previous_raw = raw;
        state.previous_base_cp = cp;
        state.previous_base_record = r;
        state.previous_at_sot = true;
        state.updateState(raw, current, cp, r);
        state.qu_pi_sp = current == .qu and r.lb_qu_pi;
        state.word_initial_hy = current == .hy or cp == 0x2010;
        return state;
    }

    pub fn resolveCurrent(self: *const State, raw: Class, cp: u21) Class {
        return self.resolveWithRecord(raw, properties.record(cp));
    }

    pub fn resolveWithRecord(self: *const State, raw: Class, r: properties.Record) Class {
        return resolve(raw, r, self.previous, self.previous_raw);
    }

    /// `next_raw`/`next_cp`/`has_next` describe the scalar following this one
    /// (class `.al`, code point 0, `has_next == false` at end of text), and
    /// `next_end` is that scalar's end offset within `bytes` so LB25 can
    /// examine the second following scalar when required.
    pub fn opportunityBefore(self: *const State, bytes: []const u8, raw: Class, current: Class, cp: u21, next_raw: Class, next_cp: u21, has_next: bool, next_end: usize) Opportunity {
        var classifier = scalar.Classifier(false){};
        return self.opportunityWithRecords(bytes, raw, current, cp, properties.record(cp), next_raw, properties.record(next_cp), has_next, next_end, &classifier);
    }

    pub fn opportunityWithRecords(self: *const State, bytes: []const u8, raw: Class, current: Class, cp: u21, r: properties.Record, next_raw: Class, next_record: properties.Record, has_next: bool, next_end: usize, classifier: anytype) Opportunity {
        return breakBefore(self.context(), bytes, raw, current, cp, r, next_raw, next_record, has_next, next_end, classifier);
    }

    pub fn consume(self: *State, raw: Class, current: Class, cp: u21) void {
        self.consumeWithRecord(raw, current, cp, properties.record(cp));
    }

    pub fn consumeRecord(self: *State, cp: u21, r: properties.Record) void {
        self.consumeWithRecord(r.line_break, self.resolveWithRecord(r.line_break, r), cp, r);
    }

    pub fn opportunityForRecord(self: *const State, bytes: []const u8, cp: u21, r: properties.Record, next_raw: Class, next_record: properties.Record, has_next: bool, next_end: usize, classifier: anytype) Opportunity {
        return self.opportunityWithRecords(bytes, r.line_break, self.resolveWithRecord(r.line_break, r), cp, r, next_raw, next_record, has_next, next_end, classifier);
    }

    pub fn consumeWithRecord(self: *State, raw: Class, current: Class, cp: u21, r: properties.Record) void {
        // This compatibility implementation is independent of generated data.
        self.consumeWithRecordGeneric(raw, current, cp, r);
    }

    /// Generic reference update retained for transition differential tests.
    fn consumeWithRecordGeneric(self: *State, raw: Class, current: Class, cp: u21, r: properties.Record) void {
        self.before_previous = self.previous;
        self.before_previous_cp = self.previous_base_cp;
        self.before_previous_record = self.previous_base_record;
        self.previous = current;
        self.previous_raw = raw;
        if (raw != .cm and raw != .zwj) self.previous_base_cp = cp;
        if (raw != .cm and raw != .zwj) self.previous_base_record = r;
        if (raw != .cm and raw != .zwj) self.previous_at_sot = false;
        self.updateState(raw, current, cp, r);
    }

    /// Generic reference decision retained for transition differential tests.
    fn opportunityWithRecordsGeneric(self: *const State, bytes: []const u8, raw: Class, current: Class, cp: u21, r: properties.Record, next_raw: Class, next_record: properties.Record, has_next: bool, next_end: usize, classifier: anytype) Opportunity {
        return breakBefore(self.context(), bytes, raw, current, cp, r, next_raw, next_record, has_next, next_end, classifier);
    }

    fn updateState(self: *State, raw: Class, current: Class, cp: u21, r: properties.Record) void {
        const was_op_sp = self.op_sp;
        const was_qu_pi_sp = self.qu_pi_sp;
        const was_cl_cp_sp = self.cl_cp_sp;
        const was_b2_sp = self.b2_sp;
        const was_num_is_sy = self.num_is_sy;
        const was_word_initial_hy = self.word_initial_hy;
        const was_aksara_vi = self.aksara_vi;
        self.zw_sp = raw == .zw or (raw == .sp and self.zw_sp);
        self.op_sp = current == .op or (raw == .sp and was_op_sp);
        self.qu_pi_sp = if (raw == .cm or raw == .zwj) was_qu_pi_sp else (current == .qu and r.lb_qu_pi and isLb15aStart(self.before_previous)) or (raw == .sp and was_qu_pi_sp);
        self.cl_cp_sp = (current == .cl or current == .cp) or (raw == .sp and was_cl_cp_sp);
        self.b2_sp = current == .b2 or (raw == .sp and was_b2_sp);
        self.hl_ba_hy = self.before_previous == .hl and (current == .hy or (current == .ba and !r.east_asian_wide));
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

    fn context(self: *const State) BreakContext {
        return .{
            .previous = self.previous,
            .previous_raw = self.previous_raw,
            .before_previous = self.before_previous,
            .previous_base_is_dotted_circle = self.previous_base_cp == 0x25CC,
            .before_previous_is_dotted_circle = self.before_previous_cp == 0x25CC,
            .previous_base_east_asian_wide = self.previous_base_record.east_asian_wide,
            .previous_base_lb_qu_pf = self.previous_base_record.lb_qu_pf,
            .previous_base_lb_cp30 = self.previous_base_record.lb_cp30,
            .previous_base_ep_cn = self.previous_base_record.ep_cn,
            .before_previous_east_asian_wide = self.before_previous_record.east_asian_wide,
            .previous_at_sot = self.previous_at_sot,
            .zw_sp = self.zw_sp,
            .op_sp = self.op_sp,
            .qu_pi_sp = self.qu_pi_sp,
            .cl_cp_sp = self.cl_cp_sp,
            .b2_sp = self.b2_sp,
            .hl_ba_hy = self.hl_ba_hy,
            .word_initial_hy = self.word_initial_hy,
            .po_pr_before_op = self.po_pr_before_op,
            .num_is_sy = self.num_is_sy,
            .number_cl_cp = self.number_cl_cp,
            .aksara_vi = self.aksara_vi,
            .ri_odd = self.ri_count % 2 == 1,
        };
    }
};

const BreakContext = packed struct(u64) {
    previous: Class,
    previous_raw: Class,
    before_previous: Class,
    previous_base_is_dotted_circle: bool,
    before_previous_is_dotted_circle: bool,
    previous_base_east_asian_wide: bool,
    previous_base_lb_qu_pf: bool,
    previous_base_lb_cp30: bool,
    previous_base_ep_cn: bool,
    before_previous_east_asian_wide: bool,
    previous_at_sot: bool,
    zw_sp: bool,
    op_sp: bool,
    qu_pi_sp: bool,
    cl_cp_sp: bool,
    b2_sp: bool,
    hl_ba_hy: bool,
    word_initial_hy: bool,
    po_pr_before_op: bool,
    num_is_sy: bool,
    number_cl_cp: bool,
    aksara_vi: bool,
    ri_odd: bool,
    _padding: u26 = 0,
};

/// The state selected for internal iterators and fused scanners.  `State`
/// remains public and source-compatible for lens consumers.
pub const ActiveState = if (build_options.line_break_engine == .machine) semantic_machine.State else State;

pub const Iterator = struct {
    bytes: []const u8,
    pos: usize = 0,
    initialized: bool = false,
    finished: bool = false,
    state: ActiveState = .{},
    next_token: ?Token = null,

    pub fn next(self: *Iterator) ?Boundary {
        if (self.finished) return null;
        if (!self.initialized) {
            self.initialized = true;
            if (self.bytes.len == 0) {
                self.finished = true;
                return .{ .offset = 0, .opportunity = .mandatory };
            }
            const token = self.takeToken();
            self.state = ActiveState.firstWithRecord(token.record.line_break, token.codepoint orelse 0, token.record);
            return .{ .offset = 0, .opportunity = .prohibited };
        }
        if (self.pos == self.bytes.len) {
            self.finished = true;
            return .{ .offset = self.pos, .opportunity = .mandatory };
        }

        const offset = self.pos;
        const token = self.takeToken();
        const cp = token.codepoint orelse 0;
        const following = self.peekToken();
        const next_raw = following.record.line_break;
        var classifier = scalar.Classifier(false){};
        const opportunity = self.state.opportunityForRecord(self.bytes, cp, token.record, next_raw, following.record, following.end != following.start, following.end, &classifier);
        self.state.consumeRecord(cp, token.record);
        return .{ .offset = offset, .opportunity = opportunity };
    }

    fn takeToken(self: *Iterator) Token {
        const token = self.next_token orelse self.decodeAt(self.pos);
        self.next_token = null;
        self.pos = token.end;
        return token;
    }

    fn peekToken(self: *Iterator) Token {
        if (self.next_token == null) self.next_token = self.decodeAt(self.pos);
        return self.next_token.?;
    }

    fn decodeAt(self: *const Iterator, offset: usize) Token {
        var classifier = scalar.Classifier(false){};
        return classifier.at(self.bytes, offset);
    }
};

pub fn iterator(bytes: []const u8) Iterator {
    return .{ .bytes = bytes };
}

pub fn isHardClass(c: Class) bool {
    return isHard(c);
}

// LB4-LB31, after LB1 resolution. Earlier rules take precedence.
fn breakBefore(it: BreakContext, bytes: []const u8, raw: Class, current: Class, cp: u21, r: properties.Record, next_raw: Class, next_record: properties.Record, has_next: bool, next_end: usize, classifier: anytype) Opportunity {
    // LB5 and LB6: preserve CRLF, and force boundaries around hard breaks.
    if (it.previous_raw == .cr and raw == .lf) return .prohibited;
    // LB4: a boundary following a hard break is mandatory.  The conformance
    // fixture only records break/no-break, so retain this stronger fact for
    // callers that turn opportunities into display lines.
    if (isHard(it.previous_raw)) return .mandatory;
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
    if (current == .qu and r.lb_qu_pf and (!has_next or isLb15bFollower(next_raw))) return .prohibited; // LB15b
    if (current == .is) return .prohibited; // LB15d
    if (it.cl_cp_sp and current == .ns) return .prohibited;
    if (it.b2_sp and current == .b2) return .prohibited;
    if (it.previous == .sp) return .allowed; // LB18
    if (current == .qu and !r.lb_qu_pi) return .prohibited; // LB19
    if (current == .qu and (!it.previous_base_east_asian_wide or !has_next or !next_record.east_asian_wide)) return .prohibited; // LB19a
    if (it.previous == .qu and it.previous_at_sot) return .prohibited; // LB19a
    if (it.previous == .qu and !it.before_previous_east_asian_wide) return .prohibited; // LB19a
    if (it.previous == .qu and !r.east_asian_wide) return .prohibited; // LB19a
    if (it.previous == .qu and !it.previous_base_lb_qu_pf) return .prohibited;
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
    if ((it.previous == .po or it.previous == .pr) and current == .op and (next_raw == .nu or secondFollowingIsNu(bytes, next_raw, next_end, classifier))) return .prohibited;
    if (it.po_pr_before_op and (current == .nu or (current == .is and next_raw == .nu))) return .prohibited;

    // LB26-LB30b: Hangul, Brahmic syllables, alphabetics, and emoji.
    if (hangulPair(it.previous, current)) return .prohibited;
    if (isHangul(it.previous) and (current == .in or current == .po)) return .prohibited;
    if (it.previous == .pr and isHangul(current)) return .prohibited;
    if (isAlphabetic(it.previous) and isAlphabetic(current)) return .prohibited;
    if (it.previous == .ap and isAksara(current, cp)) return .prohibited;
    if (isAksaraState(it.previous, it.previous_base_is_dotted_circle) and (current == .vf or current == .vi)) return .prohibited;
    if (it.aksara_vi and (current == .ak or cp == 0x25CC)) return .prohibited;
    if (isAksaraState(it.previous, it.previous_base_is_dotted_circle) and isAksara(current, cp) and next_raw == .vf) return .prohibited;
    if (it.previous == .is and isAlphabetic(current)) return .prohibited;
    if ((isAlphabetic(it.previous) or it.previous == .nu) and current == .op and r.lb_op30) return .prohibited;
    if (it.previous == .cp and it.previous_base_lb_cp30 and (isAlphabetic(current) or current == .nu)) return .prohibited;
    if (it.previous == .ri and current == .ri and it.ri_odd) return .prohibited;
    if ((it.previous == .eb or it.previous_base_ep_cn) and current == .em) return .prohibited;

    return .allowed; // LB31
}

// LB1. The fallback for malformed UTF-8 is AL in rawClass.
fn resolve(raw: Class, r: properties.Record, previous: Class, previous_raw: Class) Class {
    return switch (raw) {
        .ai, .sg, .xx => .al,
        .cj => .ns,
        .sa => if (r.lb_sa_mn_mc) .cm else .al,
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
fn isAksaraState(c: Class, is_dotted_circle: bool) bool {
    return c == .ak or c == .as or is_dotted_circle;
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
fn secondFollowingIsNu(bytes: []const u8, next_raw: Class, next_end: usize, classifier: anytype) bool {
    if (next_raw != .is) return false;
    return classifier.at(bytes, next_end).record.line_break == .nu;
}
fn hangulPair(left: Class, right: Class) bool {
    if (left == .jl) return right == .jl or right == .jv or right == .h2 or right == .h3;
    if (left == .jv or left == .h2) return right == .jv or right == .jt;
    return (left == .jt or left == .h3) and right == .jt;
}

const TransitionTestToken = scalar.ClassifiedToken;

fn expectMachineMatchesGeneric(bytes: []const u8) !void {
    errdefer std.debug.print("transition input bytes: {x}\n", .{bytes});
    var tokens: [512]TransitionTestToken = undefined;
    var count: usize = 0;
    var classifier = scalar.Classifier(false){};
    var pos: usize = 0;
    while (pos < bytes.len) {
        if (count == tokens.len) return error.TestUnexpectedResult;
        const token = classifier.at(bytes, pos);
        tokens[count] = token;
        count += 1;
        pos = token.end;
    }
    if (count == 0) return;

    const first = tokens[0];
    var hybrid = State.firstWithRecord(first.record.line_break, first.codepoint orelse 0, first.record);
    var generic = hybrid;
    var semantic = semantic_machine.State.firstWithRecord(first.record.line_break, first.codepoint orelse 0, first.record);
    var consume_only = semantic;
    var lookahead_classifier = scalar.Classifier(false){};
    const eot = lookahead_classifier.at(bytes, bytes.len);

    for (1..count) |i| {
        const token = tokens[i];
        const next = if (i + 1 < count) tokens[i + 1] else eot;
        const raw = token.record.line_break;
        const cp = token.codepoint orelse 0;
        const hybrid_current = hybrid.resolveWithRecord(raw, token.record);
        const generic_current = generic.resolveWithRecord(raw, token.record);
        try std.testing.expectEqual(generic_current, hybrid_current);
        const hybrid_opportunity = hybrid.opportunityWithRecords(bytes, raw, hybrid_current, cp, token.record, next.record.line_break, next.record, i + 1 < count, next.end, &lookahead_classifier);
        var generic_classifier = scalar.Classifier(false){};
        const generic_opportunity = generic.opportunityWithRecordsGeneric(bytes, raw, generic_current, cp, token.record, next.record.line_break, next.record, i + 1 < count, next.end, &generic_classifier);
        const saved_id = semantic.id;
        for (0..2) |_| {
            const actual = semantic.opportunityForRecord(bytes, cp, token.record, next.record.line_break, next.record, i + 1 < count, next.end, &generic_classifier);
            if (generic_opportunity != actual) std.debug.print("semantic mismatch at scalar {d}, state {d}\n", .{ i, saved_id });
            try std.testing.expectEqual(generic_opportunity, actual);
            try std.testing.expectEqual(saved_id, semantic.id);
        }
        semantic.consumeRecord(cp, token.record);
        consume_only.consumeRecord(cp, token.record);
        try std.testing.expectEqual(semantic.id, consume_only.id);
        try std.testing.expectEqual(generic_opportunity, hybrid_opportunity);
        hybrid.consumeWithRecord(raw, hybrid_current, cp, token.record);
        generic.consumeWithRecordGeneric(raw, generic_current, cp, token.record);
        try std.testing.expectEqualDeep(generic, hybrid);
    }
}

test "semantic transitions agree with generic engine" {
    const cases = [_][]const u8{
        "",
        "a",
        "ordinary alphabetic text stays ordinary",
        "Καλημέρα ελληνικά γράμματα",
        "кириллица и слова",
        "日本語の文章と漢字を測定します。",
        "a\n\r\n\xc2\x85\x0b\x0c\xe2\x80\xa8\xe2\x80\xa9b",
        "e\xcc\x81 a\xe2\x81\xa0b \xff\xc0\x80",
        "USD (1.23) and $ (45,678.90) -R",
        "🇬🇷🇬🇷 👩‍👩‍👧‍👦 👋🏿",
        "क्षि हिन्दी 한국어 조합",
    };
    for (cases) |bytes| try expectMachineMatchesGeneric(bytes);
}

test "semantic transitions across mixed contexts" {
    const atoms = [_][]const u8{
        "a",
        "界",
        " ",
        "\n",
        "\r\n",
        "(",
        ")",
        "1",
        ",",
        "-",
        "\xff",
        "e\xcc\x81",
        "🇬🇷",
        "👩‍👩‍👧‍👦",
        "क्षि",
    };
    var random = std.Random.DefaultPrng.init(0x0147_a55);
    var bytes: [512]u8 = undefined;
    for (0..400) |_| {
        var len: usize = 0;
        for (0..random.random().intRangeAtMost(usize, 1, 48)) |_| {
            const atom = atoms[random.random().uintLessThan(usize, atoms.len)];
            if (len + atom.len > bytes.len) break;
            @memcpy(bytes[len..][0..atom.len], atom);
            len += atom.len;
        }
        try expectMachineMatchesGeneric(bytes[0..len]);
    }
}

test "generated semantic machine fits its data budget" {
    const data = @import("line_break_machine_data.zig");
    try std.testing.expectEqual(@as(usize, 1), @sizeOf(semantic_machine.State));
    try std.testing.expectEqual(data.data_bytes, @sizeOf(@TypeOf(data.transitions)) + @sizeOf(@TypeOf(data.category_map)));
    try std.testing.expect(data.data_bytes <= 32 * 1024);
}

test "generated machine keeps glue before alphabetics prohibited" {
    const glue_cp: u21 = 0x00a0;
    const alphabetic_cp: u21 = 0x23e9;
    const glue_record = properties.record(glue_cp);
    const alphabetic_record = properties.record(alphabetic_cp);
    var state = State.firstWithRecord(.gl, glue_cp, glue_record);
    const current = state.resolveWithRecord(.al, alphabetic_record);
    var classifier = scalar.Classifier(false){};
    try std.testing.expectEqual(.prohibited, state.opportunityWithRecords("\xc2\xa0\xe2\x8f\xa9", .al, current, alphabetic_cp, alphabetic_record, .al, properties.record(0), false, 5, &classifier));
}

test "semantic machine exhaustive category triples and malformed tails" {
    // Select witnesses independently from the generated table: retain every
    // predicate observed by the standard, but not unrelated width/GB fields.
    var seen = [_]bool{false} ** (48 * 512);
    var witnesses: [128]u21 = undefined;
    var count: usize = 0;
    for (0..0x110000) |value| {
        if (value >= 0xd800 and value <= 0xdfff) continue;
        const cp: u21 = @intCast(value);
        const r = properties.record(cp);
        const bits = [_]bool{
            r.east_asian_wide, r.lb_qu_pi, r.lb_qu_pf,    r.lb_op30,
            r.lb_cp30,         r.ep_cn,    r.lb_sa_mn_mc, cp == 0x2010,
            cp == 0x25cc,
        };
        var key: usize = @as(usize, @intFromEnum(r.line_break)) * 512;
        for (bits, 0..) |bit, shift| key += @as(usize, @intFromBool(bit)) << @intCast(shift);
        if (seen[key]) continue;
        seen[key] = true;
        try std.testing.expect(count < witnesses.len);
        witnesses[count] = cp;
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 68), count);
    var bytes: [12]u8 = undefined;
    for (witnesses[0..count]) |a| {
        const first_end: usize = try std.unicode.utf8Encode(a, &bytes);
        for (witnesses[0..count]) |b| {
            const second_end: usize = first_end + try std.unicode.utf8Encode(b, bytes[first_end..]);
            try expectMachineMatchesGeneric(bytes[0..second_end]);
            for (witnesses[0..count]) |c| {
                const end = second_end + try std.unicode.utf8Encode(c, bytes[second_end..]);
                try expectMachineMatchesGeneric(bytes[0..end]);
            }
        }
    }
    for (0..256) |leading| {
        const malformed = [_]u8{ 'a', @intCast(leading), 0x80, 0x80, '\n', 0xe2, 0x81, 0xa0 };
        for (2..malformed.len + 1) |end| try expectMachineMatchesGeneric(malformed[0..end]);
    }
    var long_bytes: [512]u8 = undefined;
    var random = std.Random.DefaultPrng.init(0x015_cafe);
    for (0..1000) |_| {
        var len: usize = 0;
        for (0..128) |_| {
            const cp = witnesses[random.random().uintLessThan(usize, count)];
            len += try std.unicode.utf8Encode(cp, long_bytes[len..]);
        }
        try expectMachineMatchesGeneric(long_bytes[0..len]);
    }
    for ([_]u21{ ' ', 0x0300, 0x1f1e6 }) |cp| {
        var len: usize = 0;
        for (0..128) |_| len += try std.unicode.utf8Encode(cp, long_bytes[len..]);
        try expectMachineMatchesGeneric(long_bytes[0..len]);
    }
}
