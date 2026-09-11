//! Behaviour the UAX #29 fixture does not pin: the span contract, the
//! `is_word` flag, malformed input, and the traversal work bound.
const std = @import("std");
const word = @import("segmentation").word;

const Expected = struct {
    start: usize,
    end: usize,
    is_word: bool,
};

/// Checks the spans and, at the same time, the partition contract: the first
/// starts at zero, each start meets the previous end, and the last ends at
/// `bytes.len`.
fn expectSegments(bytes: []const u8, expected: []const Expected) !void {
    try expectSegmentsFrom(word.iterator(bytes), bytes, expected);
    // Every case in this file is also a differential case: the compiled
    // decision table and the directly evaluated rules must agree.
    try expectSegmentsFrom(word.referenceIterator(bytes), bytes, expected);
}

fn expectSegmentsFrom(iterator: anytype, bytes: []const u8, expected: []const Expected) !void {
    var it = iterator;
    var index: usize = 0;
    var cursor: usize = 0;
    while (it.next()) |span| : (index += 1) {
        if (index >= expected.len) {
            std.debug.print("extra span {d}..{d}\n", .{ span.start, span.end });
            return error.TestUnexpectedResult;
        }
        const want = expected[index];
        std.testing.expectEqual(want.start, span.start) catch |err| {
            std.debug.print("span {d}: start\n", .{index});
            return err;
        };
        std.testing.expectEqual(want.end, span.end) catch |err| {
            std.debug.print("span {d}: end\n", .{index});
            return err;
        };
        std.testing.expectEqual(want.is_word, span.is_word) catch |err| {
            std.debug.print("span {d} ({d}..{d} = \"{f}\"): is_word\n", .{ index, span.start, span.end, std.ascii.hexEscape(bytes[span.start..span.end], .lower) });
            return err;
        };
        try std.testing.expect(span.start == cursor);
        try std.testing.expect(span.end > span.start);
        cursor = span.end;
    }
    try std.testing.expectEqual(expected.len, index);
    try std.testing.expectEqual(bytes.len, cursor);
    // Exhaustion is stable.
    try std.testing.expectEqual(@as(?word.Span, null), it.next());
    try std.testing.expectEqual(@as(?word.Span, null), it.next());
}

fn w(start: usize, end: usize) Expected {
    return .{ .start = start, .end = end, .is_word = true };
}

fn n(start: usize, end: usize) Expected {
    return .{ .start = start, .end = end, .is_word = false };
}

test "worked example" {
    const line = "The price is $9.99 -unless you pay cash.";
    try std.testing.expectEqual(@as(usize, 40), line.len);
    try expectSegments(line, &.{
        w(0, 3), n(3, 4), // The
        w(4, 9), n(9, 10), // price
        w(10, 12), n(12, 13), // is
        n(13, 14), // $
        w(14, 18), n(18, 19), // 9.99: WB11/WB12 keep the decimal point inside
        n(19, 20), // -: WB=Other, so it breaks off
        w(20, 26), n(26, 27), // unless
        w(27, 30), n(30, 31), // you
        w(31, 34), n(34, 35), // pay
        w(35, 39), // cash
        n(39, 40), // .: no following letter, so WB6 does not bridge
    });
}

test "empty input yields no spans" {
    var it = word.iterator("");
    try std.testing.expectEqual(@as(?word.Span, null), it.next());
    try std.testing.expectEqual(@as(?word.Span, null), it.next());
}

test "single scalar" {
    try expectSegments("a", &.{w(0, 1)});
    try expectSegments(" ", &.{n(0, 1)});
    try expectSegments("\u{4E00}", &.{w(0, 3)});
    try expectSegments("\u{0308}", &.{n(0, 2)});
}

test "offsets are relative to the slice the view was opened on" {
    const backing = "xx" ++ "hi there" ++ "yy";
    try expectSegments(backing[2..10], &.{ w(0, 2), n(2, 3), w(3, 8) });
}

test "scripts and the is_word predicate" {
    // Han and Thai are WB=Other yet Alphabetic, so the flag cannot be
    // inferred from Word_Break. Neither can the default rules segment them.
    try expectSegments("\u{4E00}\u{4E8C}", &.{ w(0, 3), w(3, 6) });
    try expectSegments("\u{0E01}\u{0E02}", &.{ w(0, 3), w(3, 6) });
    // Katakana joins by WB13.
    try expectSegments("\u{30AB}\u{30AD}", &.{w(0, 6)});
    // Arabic-Indic digits are WB=Numeric and GC=Nd.
    try expectSegments("\u{0660}\u{0661}", &.{w(0, 4)});
    // U+00B2 is WB=Other and GC=No: word-like, but its own segment.
    try expectSegments("\u{00B2}", &.{w(0, 2)});
    // U+2160 is Nl and Alphabetic, and WB=ALetter.
    try expectSegments("\u{2160}\u{2161}", &.{w(0, 6)});
    // Underscore is ExtendNumLet and GC=Pc: not word-like on its own.
    try expectSegments("_", &.{n(0, 1)});
    try expectSegments("_a", &.{w(0, 2)});
    // Emoji are WB=Other and not Alphabetic.
    try expectSegments("\u{1F600}", &.{n(0, 4)});
    // Alphabetic combining marks are word-like; other marks are not. Both are
    // WB=Extend, so this is a pure flag difference.
    try expectSegments("\u{0345}", &.{w(0, 2)});
    try expectSegments("\u{0308}", &.{n(0, 2)});
}

test "apostrophes and quotes" {
    // WB6/WB7 bridge a MidNumLetQ between letters.
    try expectSegments("don't", &.{w(0, 5)});
    try expectSegments("don\u{2019}t", &.{w(0, 7)});
    // No letter after the apostrophe: the bridge fails on both sides.
    try expectSegments("don'", &.{ w(0, 3), n(3, 4) });
    try expectSegments("don' ", &.{ w(0, 3), n(3, 4), n(4, 5) });
    // WB7a attaches a single quote to a Hebrew letter with no lookahead.
    try expectSegments("\u{05D0}'", &.{w(0, 3)});
    // WB7b/WB7c bridge a double quote between Hebrew letters.
    try expectSegments("\u{05D0}\"\u{05D1}", &.{w(0, 5)});
    // The same double quote with no Hebrew letter after it, and at EOF.
    try expectSegments("\u{05D0}\"!", &.{ w(0, 2), n(2, 3), n(3, 4) });
    try expectSegments("\u{05D0}\"", &.{ w(0, 2), n(2, 3) });
    // A double quote does not bridge ordinary letters.
    try expectSegments("a\"b", &.{ w(0, 1), n(1, 2), w(2, 3) });
}

test "newlines" {
    // WB3 keeps CRLF together; WB3a/WB3b isolate every other terminator.
    try expectSegments("a\r\nb", &.{ w(0, 1), n(1, 3), w(3, 4) });
    try expectSegments("a\n\rb", &.{ w(0, 1), n(1, 2), n(2, 3), w(3, 4) });
    try expectSegments("a\u{0085}b", &.{ w(0, 1), n(1, 3), w(3, 4) });
    try expectSegments("a\u{2028}b", &.{ w(0, 1), n(1, 4), w(4, 5) });
    try expectSegments("a\u{000B}b", &.{ w(0, 1), n(1, 2), w(2, 3) });
}

test "WB4 does not fold at start of text or after a newline" {
    // At start of text WB1 has already broken, so the mark stands alone.
    try expectSegments("\u{0308}a", &.{ n(0, 2), w(2, 3) });
    // WB3a breaks after the newline, so the mark cannot attach to it either,
    // and it does not become a base for the letter that follows.
    try expectSegments("\n\u{0308}a", &.{ n(0, 1), n(1, 3), w(3, 4) });
    try expectSegments("\r\n\u{0308}a", &.{ n(0, 2), n(2, 4), w(4, 5) });
    // Everywhere else it folds into the character before it.
    try expectSegments("a\u{0308}b", &.{w(0, 4)});
    try expectSegments(".\u{0308}", &.{n(0, 3)});
}

test "WB3c and WB3d read raw adjacency, not the folded context" {
    // WB3d joins two spaces, and an intervening mark breaks that adjacency.
    try expectSegments("  ", &.{n(0, 2)});
    try expectSegments(" \u{0308} ", &.{ n(0, 3), n(3, 4) });
    // WB3c joins ZWJ to a pictograph. A Format character between them is
    // folded into the ZWJ but still breaks the raw adjacency WB3c needs.
    try expectSegments("a\u{200D}\u{1F600}", &.{w(0, 8)});
    try expectSegments("a\u{200D}\u{00AD}\u{1F600}", &.{ w(0, 6), n(6, 10) });
}

test "regional indicators pair up, and folded characters do not reset them" {
    const ri = "\u{1F1E6}";
    try expectSegments(ri ** 2, &.{n(0, 8)});
    try expectSegments(ri ** 4, &.{ n(0, 8), n(8, 16) });
    try expectSegments(ri ** 5, &.{ n(0, 8), n(8, 16), n(16, 20) });
    // The mark folds into the first indicator, so the pair still forms.
    try expectSegments(ri ++ "\u{0308}" ++ ri, &.{n(0, 10)});
    // A letter between them resets the parity.
    try expectSegments(ri ++ "a" ++ ri ++ ri, &.{ n(0, 4), w(4, 5), n(5, 13) });
}

/// `head`, then `run` repeated `count` times, then `tail`.
fn build(buffer: []u8, head: []const u8, run: []const u8, count: usize, tail: []const u8) []const u8 {
    var len: usize = 0;
    @memcpy(buffer[len..][0..head.len], head);
    len += head.len;
    for (0..count) |_| {
        @memcpy(buffer[len..][0..run.len], run);
        len += run.len;
    }
    @memcpy(buffer[len..][0..tail.len], tail);
    return buffer[0 .. len + tail.len];
}

test "long folded runs inside a punctuation bridge" {
    var buffer: [8192]u8 = undefined;
    // U+0345 is Alphabetic and WB=Extend, so the run is word-like and is
    // crossed by the WB6/WB12/WB7b lookahead. Its flag must land in the
    // segment that actually contains it, never in the one being emitted.
    for ([_][]const u8{ "\u{0308}", "\u{0345}", "\u{00AD}", "\u{200D}" }) |mark| {
        for ([_]usize{ 1, 2, 500 }) |count| {
            const bytes = mark.len * count;
            // WB6/WB7: the bridge succeeds, so everything is one segment.
            try expectSegments(build(&buffer, "a.", mark, count, "b"), &.{w(0, 3 + bytes)});
            // WB12/WB11 across the same run.
            try expectSegments(build(&buffer, "1,", mark, count, "2"), &.{w(0, 3 + bytes)});
            // WB7b/WB7c across the same run.
            try expectSegments(build(&buffer, "\u{05D0}\"", mark, count, "\u{05D1}"), &.{w(0, 5 + bytes)});

            // The bridge fails: the punctuation and the run it absorbed form
            // their own segment, word-like only when the run is.
            const marked = std.mem.eql(u8, mark, "\u{0345}");
            try expectSegments(build(&buffer, "a.", mark, count, "!"), &.{
                w(0, 1),
                .{ .start = 1, .end = 2 + bytes, .is_word = marked },
                n(2 + bytes, 3 + bytes),
            });
            // And the same candidate at end of text.
            try expectSegments(build(&buffer, "a.", mark, count, ""), &.{
                w(0, 1),
                .{ .start = 1, .end = 2 + bytes, .is_word = marked },
            });
        }
    }
}

test "a lookahead never leaks its flag into the segment it is deciding" {
    // U+05F3 is WB=ALetter but not Alphabetic, so its segment must stay
    // non-word even though the WB6 lookahead crosses an Alphabetic mark.
    try expectSegments("\u{05F3}.\u{0345}!", &.{
        n(0, 2),
        w(2, 5), // the period plus the mark it folded in
        n(5, 6),
    });
}

test "malformed input is WB=Other, one byte at a time" {
    try expectSegments("a\xffb", &.{ w(0, 1), n(1, 2), w(2, 3) });
    // A following mark still folds into it by WB4.
    try expectSegments("a\xff\u{0308}b", &.{ w(0, 1), n(1, 4), w(4, 5) });
    // Each invalid byte stands alone.
    try expectSegments("\xff\xfe", &.{ n(0, 1), n(1, 2) });
    // Overlong, surrogate and out-of-range encodings decode one byte at a time.
    try expectSegments("\xc0\x80", &.{ n(0, 1), n(1, 2) });
    try expectSegments("\xed\xa0\x80", &.{ n(0, 1), n(1, 2), n(2, 3) });
    try expectSegments("\xf5\x80\x80\x80", &.{ n(0, 1), n(1, 2), n(2, 3), n(3, 4) });
    // Truncated tails.
    try expectSegments("a\xe2\x82", &.{ w(0, 1), n(1, 2), n(2, 3) });
    try expectSegments("a\xf0\x9f\x91", &.{ w(0, 1), n(1, 2), n(2, 3), n(3, 4) });
    // An invalid byte at each contextual position of a punctuation bridge.
    try expectSegments("a.\xffb", &.{ w(0, 1), n(1, 2), n(2, 3), w(3, 4) });
    try expectSegments("\xff.b", &.{ n(0, 1), n(1, 2), w(2, 3) });
    try expectSegments("1,\xff2", &.{ w(0, 1), n(1, 2), n(2, 3), w(3, 4) });
    try expectSegments("\u{05D0}\"\xff\u{05D1}", &.{ w(0, 2), n(2, 3), n(3, 4), w(4, 6) });
}

test "traversal is linear in the input" {
    var buffer: [65536]u8 = undefined;
    for ([_]usize{ 16, 64, 256, 1024, 4096 }) |count| {
        // Every gap that can request lookahead does, and every lookahead
        // crosses a folded run: the adversarial shape for the work bound.
        const bytes = build(&buffer, "", "a.\u{0308}\u{0308}\u{0308}", count, "");
        var it = word.instrumentedIterator(bytes);
        while (it.next()) |_| {}

        const scalars = 5 * count;
        try std.testing.expectEqual(scalars, it.counters.scalars);
        // Each folded run follows exactly one character, and only one rule
        // can request a lookahead at a gap, so no run is crossed twice.
        try std.testing.expect(it.counters.lookahead_scalars <= scalars);
        try std.testing.expect(it.counters.scalars + it.counters.lookahead_scalars <= 2 * scalars);
    }
}

test "long regional-indicator runs keep their parity across folded marks" {
    var buffer: [8192]u8 = undefined;
    var expected: [512]Expected = undefined;
    // Each indicator absorbs a mark by WB4, so the run is still (RI RI)* for
    // WB15/WB16 and pairs up two indicators, twelve bytes, at a time.
    for ([_]usize{ 1, 2, 3, 500, 501 }) |count| {
        const bytes = build(&buffer, "", "\u{1F1E6}\u{0308}", count, "");
        var len: usize = 0;
        var pos: usize = 0;
        while (pos < bytes.len) : (len += 1) {
            const end = @min(pos + 12, bytes.len);
            expected[len] = n(pos, end);
            pos = end;
        }
        try expectSegments(bytes, expected[0..len]);
    }
}

/// One code point per distinct `(Word_Break, word_like, Extended_Pictographic)`
/// key that actually occurs, discovered from the pinned table rather than
/// listed by hand, so a witness set can never fall behind the data.
fn witnesses(buffer: []u21) []const u21 {
    const word_properties = @import("tables").word;
    var seen = std.StaticBitSet(128).initEmpty();
    var len: usize = 0;
    var cp: u21 = 0;
    while (cp < 0x110000) : (cp += 1) {
        if (cp >= 0xD800 and cp <= 0xDFFF) continue;
        const key: u7 = @truncate(@as(u8, @bitCast(word_properties.wordProperties(cp))));
        if (seen.isSet(key)) continue;
        seen.set(key);
        buffer[len] = cp;
        len += 1;
    }
    return buffer[0..len];
}

fn expectSameSegmentation(bytes: []const u8) !void {
    var tabled = word.iterator(bytes);
    var reference = word.referenceIterator(bytes);
    while (true) {
        const a = tabled.next();
        const b = reference.next();
        std.testing.expectEqualDeep(b, a) catch |err| {
            std.debug.print("diverged on \"{f}\"\n", .{std.ascii.hexEscape(bytes, .lower)});
            return err;
        };
        if (a == null) return;
    }
}

test "the compiled table decides exactly as the rules do" {
    const classes = @typeInfo(word.WordBreak).@"enum".fields.len;
    for (0..classes) |sig| {
        for (0..classes) |sig_prev| {
            for (0..2) |parity| {
                for (0..classes) |cur| {
                    const args = .{
                        @as(word.WordBreak, @enumFromInt(sig)),
                        @as(word.WordBreak, @enumFromInt(sig_prev)),
                        parity == 1,
                        @as(word.WordBreak, @enumFromInt(cur)),
                    };
                    try std.testing.expectEqualDeep(
                        @call(.auto, word.lateDecision, args),
                        @call(.auto, word.machine.decide, args),
                    );
                }
            }
        }
    }
    // The table is smaller than the state space only because rows repeat, and
    // the budget is the plan's, not something the machine may grow past.
    try std.testing.expect(word.machine.row_count < word.machine.state_count);
    try std.testing.expect(word.machine.data_bytes <= 8 * 1024);
}

test "both engines agree over every witness pair, triple and quadruple" {
    var buffer: [128]u21 = undefined;
    const points = witnesses(&buffer);
    // Enough for WB7c and WB11, which read two characters of left context,
    // plus the character at the gap and the one a lookahead asks for.
    try std.testing.expect(points.len >= 19);

    var bytes: [16]u8 = undefined;
    for (points) |a| {
        const la: usize = try std.unicode.utf8Encode(a, bytes[0..]);
        try expectSameSegmentation(bytes[0..la]);
        for (points) |b| {
            const lb: usize = la + try std.unicode.utf8Encode(b, bytes[la..]);
            try expectSameSegmentation(bytes[0..lb]);
            for (points) |c| {
                const lc: usize = lb + try std.unicode.utf8Encode(c, bytes[lb..]);
                try expectSameSegmentation(bytes[0..lc]);
                for (points) |d| {
                    const ld: usize = lc + try std.unicode.utf8Encode(d, bytes[lc..]);
                    try expectSameSegmentation(bytes[0..ld]);
                }
            }
        }
    }
}

test "both engines agree over the fixture and over random bytes" {
    const fixture = @embedFile("data/WordBreakTest-17.0.0.txt");
    var lines = std.mem.splitScalar(u8, fixture, '\n');
    while (lines.next()) |raw_line| {
        const line = raw_line[0 .. std.mem.indexOfScalar(u8, raw_line, '#') orelse raw_line.len];
        if (std.mem.trim(u8, line, " \t\r").len == 0) continue;
        var bytes: [256]u8 = undefined;
        var len: usize = 0;
        var tokens = std.mem.tokenizeAny(u8, line, " \t\r");
        while (tokens.next()) |token| {
            if (std.mem.eql(u8, token, "÷") or std.mem.eql(u8, token, "×")) continue;
            const cp = std.fmt.parseInt(u21, token, 16) catch return error.TestUnexpectedResult;
            len += std.unicode.utf8Encode(cp, bytes[len..]) catch return error.TestUnexpectedResult;
        }
        try expectSameSegmentation(bytes[0..len]);
    }

    // Raw random bytes reach the malformed path; random witnesses reach the
    // contextual rules far more often than random bytes would.
    var witness_buffer: [128]u21 = undefined;
    const points = witnesses(&witness_buffer);
    var prng = std.Random.DefaultPrng.init(0x016_b0bedcafe);
    const random = prng.random();
    var bytes: [512]u8 = undefined;
    for (0..2000) |_| {
        const len = random.intRangeAtMost(usize, 0, bytes.len);
        random.bytes(bytes[0..len]);
        try expectSameSegmentation(bytes[0..len]);
    }
    for (0..2000) |_| {
        var len: usize = 0;
        while (len + 4 <= bytes.len and random.boolean()) {
            len += std.unicode.utf8Encode(points[random.uintLessThan(usize, points.len)], bytes[len..]) catch unreachable;
        }
        try expectSameSegmentation(bytes[0..len]);
    }
}

// The reference iterator deliberately bypasses the ASCII scanner.
test "ASCII shortcut matches every byte and every pair" {
    var bytes: [2]u8 = undefined;
    for (0..128) |a| {
        bytes[0] = @intCast(a);
        try expectSameSegmentation(bytes[0..1]);
        for (0..128) |b| {
            bytes[1] = @intCast(b);
            try expectSameSegmentation(&bytes);
        }
    }
}

test "ASCII shortcut preserves four-character punctuation contexts" {
    // Every ASCII word class, with distinct letter/digit spellings and case.
    const alphabet = "Aa09_ ':.,;\"\r\n\x0b\t\x00\x7f";
    var bytes: [4]u8 = undefined;
    for (alphabet) |a| {
        bytes[0] = a;
        for (alphabet) |b| {
            bytes[1] = b;
            for (alphabet) |c| {
                bytes[2] = c;
                for (alphabet) |d| {
                    bytes[3] = d;
                    try expectSameSegmentation(&bytes);
                }
            }
        }
    }
}

test "ASCII shortcut matches long runs and falls back at every byte position" {
    var prng = std.Random.DefaultPrng.init(0xa5c11_29);
    const random = prng.random();
    var bytes: [1024]u8 = undefined;
    for (0..1000) |_| {
        const len = random.intRangeAtMost(usize, 0, bytes.len);
        random.bytes(bytes[0..len]);
        for (bytes[0..len]) |*byte| byte.* &= 0x7f;
        try expectSameSegmentation(bytes[0..len]);
    }
    // Exercise vector boundaries, short tails, and non-ASCII at every offset.
    for (1..130) |len| {
        @memset(bytes[0..len], 'a');
        try expectSameSegmentation(bytes[0..len]);
        for (0..len) |pos| {
            bytes[pos] = 0xff;
            try expectSameSegmentation(bytes[0..len]);
            bytes[pos] = 'a';
        }
    }
    for ([_][]const u8{ "\u{0308}", "\u{200d}", "\u{00e9}", "\u{05d0}", "\u{1f1e6}" }) |suffix| {
        const text = build(&bytes, "", "abc_12 ", 100, suffix);
        try expectSameSegmentation(text);
    }
    try expectSegments("a.\u{0308}b", &.{w(0, 5)});
    try expectSegments("1,\u{0308}2", &.{w(0, 5)});
}

test "ASCII iterator copies keep independent progress and stable exhaustion" {
    const bytes = "__ alpha_9 can't 1,000 \r\n";
    var original = word.iterator(bytes);
    var initial_copy = original;
    try std.testing.expectEqualDeep(original.next(), initial_copy.next());
    var copy = original;
    while (original.next()) |span| try std.testing.expectEqualDeep(span, copy.next().?);
    try std.testing.expectEqual(@as(?word.Span, null), copy.next());
    try std.testing.expectEqual(@as(?word.Span, null), original.next());
    var counted = word.instrumentedIterator(bytes);
    while (counted.next()) |_| {}
    try std.testing.expectEqual(bytes.len, counted.counters.scalars);
}
