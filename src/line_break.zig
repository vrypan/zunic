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

pub const Opportunity = semantic_machine.Opportunity;
pub const Boundary = struct { offset: usize, opportunity: Opportunity };

const Class = properties.LineBreak;

const Token = scalar.ClassifiedToken;

/// Generated transition state shared by the iterator and fused scanner.
pub const State = semantic_machine.State;

pub const Iterator = struct {
    bytes: []const u8,
    pos: usize = 0,
    initialized: bool = false,
    finished: bool = false,
    state: State = .{},
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
            self.state = State.firstWithRecord(token.record.line_break, token.codepoint orelse 0, token.record);
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
    return c == .bk or c == .cr or c == .lf or c == .nl;
}

// Protocol consistency, not an independent Unicode oracle. Conformance tests
// compare Iterator output directly with the pinned standard fixtures.
fn expectMachineProtocol(bytes: []const u8) !void {
    errdefer std.debug.print("transition input bytes: {x}\n", .{bytes});
    var it = iterator(bytes);
    var classifier = scalar.Classifier(false){};
    var state = State{};
    var consume_only = State{};
    var pos: usize = 0;
    while (pos < bytes.len) {
        const token = classifier.at(bytes, pos);
        const next = classifier.at(bytes, token.end);
        const cp = token.codepoint orelse 0;
        const saved_id = state.id;
        const opportunity = state.opportunityForRecord(bytes, cp, token.record, next.record.line_break, next.record, token.end < bytes.len, next.end, &classifier);
        try std.testing.expectEqual(saved_id, state.id);
        try std.testing.expectEqual(opportunity, state.opportunityForRecord(bytes, cp, token.record, next.record.line_break, next.record, token.end < bytes.len, next.end, &classifier));
        try std.testing.expectEqual(saved_id, state.id);
        var copy = it;
        const boundary = it.next() orelse return error.TestUnexpectedResult;
        try std.testing.expectEqualDeep(boundary, copy.next().?);
        try std.testing.expectEqual(pos, boundary.offset);
        try std.testing.expectEqual(opportunity, boundary.opportunity);
        state.consumeRecord(cp, token.record);
        consume_only.consumeRecord(cp, token.record);
        try std.testing.expectEqual(state.id, consume_only.id);
        try std.testing.expectEqual(state.id, it.state.id);
        pos = token.end;
    }
    const eot = it.next() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualDeep(Boundary{ .offset = bytes.len, .opportunity = .mandatory }, eot);
    try std.testing.expect(it.next() == null);
    try std.testing.expect(it.next() == null);
}

test "machine iterator and state protocol agree" {
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
    for (cases) |bytes| try expectMachineProtocol(bytes);
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
        try expectMachineProtocol(bytes[0..len]);
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
    var classifier = scalar.Classifier(false){};
    try std.testing.expectEqual(.prohibited, state.opportunityForRecord("\xc2\xa0\xe2\x8f\xa9", alphabetic_cp, alphabetic_record, .al, properties.record(0), false, 5, &classifier));
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
            try expectMachineProtocol(bytes[0..second_end]);
            for (witnesses[0..count]) |c| {
                const end = second_end + try std.unicode.utf8Encode(c, bytes[second_end..]);
                try expectMachineProtocol(bytes[0..end]);
            }
        }
    }
    for (0..256) |leading| {
        const malformed = [_]u8{ 'a', @intCast(leading), 0x80, 0x80, '\n', 0xe2, 0x81, 0xa0 };
        for (2..malformed.len + 1) |end| try expectMachineProtocol(malformed[0..end]);
    }
    var long_bytes: [512]u8 = undefined;
    var random = std.Random.DefaultPrng.init(0x015_cafe);
    for (0..1000) |_| {
        var len: usize = 0;
        for (0..128) |_| {
            const cp = witnesses[random.random().uintLessThan(usize, count)];
            len += try std.unicode.utf8Encode(cp, long_bytes[len..]);
        }
        try expectMachineProtocol(long_bytes[0..len]);
    }
    for ([_]u21{ ' ', 0x0300, 0x1f1e6 }) |cp| {
        var len: usize = 0;
        for (0..128) |_| len += try std.unicode.utf8Encode(cp, long_bytes[len..]);
        try expectMachineProtocol(long_bytes[0..len]);
    }
}
