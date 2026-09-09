const std = @import("std");
const zunic = @import("zunic");

test "stripAnsi removes commands without interpreting content" {
    const cases = [_]struct { input: []const u8, output: []const u8 }{
        .{ .input = "", .output = "" },
        .{ .input = "plain\r\n\t\x00\xff", .output = "plain\r\n\t\x00\xff" },
        .{ .input = "\x1b[31mred\x1b[0m", .output = "red" },
        .{ .input = "e\x1b[31m\u{0301}", .output = "e\u{0301}" },
        .{ .input = "\xc3\x1b[0m\xa9", .output = "\xc3\xa9" },
        .{ .input = "\xff\x1b[2C\xfe\x1b]0;\xff\x07!", .output = "\xff\xfe!" },
        .{ .input = "\x1b]8;;url\x1b\\link\x1b]8;;\x1b\\", .output = "link" },
        .{ .input = "\x1b[31m\x1b]0;title\x07", .output = "" },
        .{ .input = "\x1b[31", .output = "\x1b[31" },
        .{ .input = "\x1b]broken\n", .output = "\x1b]broken\n" },
        .{ .input = "\x1bPother\x1b\\", .output = "\x1bPother\x1b\\" },
        .{ .input = "\x1b]\x1b[0mx", .output = "\x1b]x" },
    };
    for (cases) |case| {
        var buffer: [128]u8 = @splat(0xa5);
        const result = try zunic.terminal(case.input).stripAnsi(buffer[0..case.output.len]);
        try std.testing.expectEqualStrings(case.output, result);
        try std.testing.expectEqual(@intFromPtr(&buffer), @intFromPtr(result.ptr));
        try std.testing.expectEqual(@as(u8, 0xa5), buffer[result.len]); // No terminator.
    }
    // Every isolated byte is retained, including malformed UTF-8 and controls.
    for (0..256) |byte| {
        const input = [_]u8{@intCast(byte)};
        var output: [1]u8 = undefined;
        try std.testing.expectEqualSlices(u8, &input, try zunic.terminal(&input).stripAnsi(&output));
    }
}

test "stripAnsi capacity, partial writes and in-place compaction" {
    var empty: [0]u8 = .{};
    try std.testing.expectEqual(@as(usize, 0), (try zunic.terminal("\x1b[0m").stripAnsi(&empty)).len);
    try std.testing.expectError(error.NoSpace, zunic.terminal("x").stripAnsi(&empty));
    var short: [1]u8 = undefined;
    try std.testing.expectError(error.NoSpace, zunic.terminal("\x1b[31mé").stripAnsi(&short));
    try std.testing.expectEqual(@as(u8, 0xc3), short[0]); // Byte-only partial output.
    var input = "\x1b[31mcafé\x1b[0m".*;
    const result = try zunic.terminal(&input).stripAnsi(&input);
    try std.testing.expectEqualStrings("café", result);
}

// Test helper for asserting the content subsequence of token traversal.
const ContentIterator = struct {
    inner: @TypeOf(zunic.terminal("").tokens().iterator()),
    fn next(self: *ContentIterator) error{EscapeInsideGrapheme}!?zunic.Span {
        while (try self.inner.next()) |token| switch (token) {
            .grapheme => |span| return span,
            .escape => {},
        };
        return null;
    }
};
fn contentIterator(bytes: []const u8) ContentIterator {
    return .{ .inner = zunic.terminal(bytes).tokens().iterator() };
}

fn expectSpans(bytes: []const u8, expected: []const []const u8) !void {
    var it = contentIterator(bytes);
    for (expected) |value| {
        const span = (try it.next()) orelse return error.TestUnexpectedResult;
        try std.testing.expectEqualStrings(value, bytes[span.start.value..span.end.value]);
    }
    try std.testing.expect((try it.next()) == null);
    try std.testing.expect((try it.next()) == null);
}

test "terminal graphemes skip complete CSI and OSC" {
    try expectSpans("", &.{});
    try expectSpans("\x1b[31m\x1b[0m", &.{});
    try expectSpans("\x1b[31mred\x1b[0m", &.{ "r", "e", "d" });
    try expectSpans("a\x1b[38:2::12:34:56mb\x1b[0m", &.{ "a", "b" });
    try expectSpans("\x1b[?25la\x1b[1 q", &.{"a"});
    try expectSpans("\x1b]8;;https://example.com\x1b\\hi\x1b]8;;\x1b\\", &.{ "h", "i" });
    try expectSpans("\x1b]0;café\x07a\x1b]8;;\x07", &.{"a"});
    try expectSpans("\x1b]0;only a title\x07", &.{});
}

test "escapes inside graphemes fail when the joining content is reached" {
    const inputs = [_][]const u8{
        "e\x1b[31m\u{0301}",
        "👩\x1b[1m\u{200d}💻",
        "👩\u{200d}\x1b[0m💻",
        "🇬\x1b[31m🇷",
        "\r\x1b[0m\n",
        "e\x1b[1m\x1b[0m\u{0301}",
        "e\x1b[2C\u{0301}", // Ignored commands cannot silently split clusters either.
        "e\x1b]0;title\x07\u{0301}",
    };
    for (inputs) |bytes| {
        var it = contentIterator(bytes);
        const prefix = (try it.next()).?;
        try std.testing.expectEqual(@as(usize, 0), prefix.start.value);
        try std.testing.expectEqual(std.mem.indexOfScalar(u8, bytes, 0x1b).?, prefix.end.value);
        try std.testing.expectError(error.EscapeInsideGrapheme, it.next());
        try std.testing.expectError(error.EscapeInsideGrapheme, it.next());
        var copy = it;
        try std.testing.expectError(error.EscapeInsideGrapheme, copy.next());
    }
    var it = contentIterator("ae\x1b[31m\u{0301}z");
    const first = (try it.next()).?;
    try std.testing.expectEqual(@as(usize, 0), first.start.value);
    try std.testing.expectEqual(@as(usize, 1), first.end.value);
    const prefix = (try it.next()).?;
    try std.testing.expectEqual(@as(usize, 1), prefix.start.value);
    try std.testing.expectEqual(@as(usize, 2), prefix.end.value);
    try std.testing.expectError(error.EscapeInsideGrapheme, it.next());
    try expectSpans("e\u{0301}\x1b[0mx", &.{ "e\u{0301}", "x" });
    try expectSpans("🇬🇷\x1b[0m🇫🇷", &.{ "🇬🇷", "🇫🇷" });
    try expectSpans("\x1b[31m\u{0301}", &.{"\u{0301}"});
}

test "plain and malformed input follow the text view" {
    const inputs = [_][]const u8{
        "hello café 👩‍💻\r\n",
        "\xff\xc0\xaf\xed\xa0\x80",
        "\x1b",
        "\x1b[",
        "\x1b[31",
        "\x1b[1 2m",
        "\x1b]unfinished",
        "\x1b]bad\ntext\x07",
        "\x1b]bad\x7ftext\x07",
        "\x1bPpayload\x1b\\",
        "\x9b31m",
        "\u{009b}31m",
    };
    for (inputs) |bytes| {
        var plain = zunic.text(bytes).graphemes().iterator();
        var terminal = contentIterator(bytes);
        while (plain.next()) |expected| {
            try std.testing.expectEqualDeep(expected, (try terminal.next()).?);
        }
        try std.testing.expect((try terminal.next()) == null);
    }
    // A malformed escape does not prevent recognizing a later complete one.
    try expectSpans("\x1b]\x1b[31mx", &.{ "\x1b", "]", "x" });
    try expectSpans("\xff\x1b[0ma", &.{ "\xff", "a" });
}

test "terminal iterators borrow substrings and copy their traversal state" {
    const outer = "prefix\x1b[31mab\x1b[0m";
    const view = zunic.terminal(outer[6..]);
    var it = contentIterator(view.bytes);
    const first = (try it.next()).?;
    try std.testing.expectEqual(@as(usize, 5), first.start.value);
    try std.testing.expectEqual(@as(usize, 6), first.end.value);
    var copy = it;
    try std.testing.expectEqualDeep((try it.next()), (try copy.next()));
    try std.testing.expect((try it.next()) == null);
    try std.testing.expect((try copy.next()) == null);
    var fresh = contentIterator(view.bytes);
    try std.testing.expectEqualDeep(first, (try fresh.next()).?);
}

test "Unicode 16 fixture accepts escapes only at grapheme boundaries" {
    const fixture = @embedFile("data/GraphemeBreakTest-16.0.0.txt");
    var lines = std.mem.splitScalar(u8, fixture, '\n');
    while (lines.next()) |raw| {
        const line = raw[0 .. std.mem.indexOfScalar(u8, raw, '#') orelse raw.len];
        if (std.mem.trim(u8, line, " \t\r").len == 0) continue;
        var plain: [512]u8 = undefined;
        var boundaries: [128]usize = undefined;
        var count: usize = 0;
        var positions: [128]usize = undefined;
        var position_count: usize = 0;
        var len: usize = 0;
        var tokens = std.mem.tokenizeAny(u8, line, " \t\r");
        while (tokens.next()) |token| {
            if (std.mem.eql(u8, token, "÷") or std.mem.eql(u8, token, "×")) {
                positions[position_count] = len;
                position_count += 1;
                if (std.mem.eql(u8, token, "÷")) {
                    boundaries[count] = len;
                    count += 1;
                }
                continue;
            }
            len += try std.unicode.utf8Encode(try std.fmt.parseInt(u21, token, 16), plain[len..]);
        }
        // Insert SGR at each scalar boundary separately, testing both legal
        // boundaries and joins. This includes RI parity, ZWJ and Indic context.
        for (positions[0..position_count]) |split| {
            const escape = "\x1b[31m\x1b[0m";
            var decorated: [1024]u8 = undefined;
            @memcpy(decorated[0..split], plain[0..split]);
            @memcpy(decorated[split..][0..escape.len], escape);
            @memcpy(decorated[split + escape.len ..][0 .. len - split], plain[split..len]);
            var it = contentIterator(decorated[0 .. len + escape.len]);
            var rejected = false;
            for (boundaries[0 .. count - 1], boundaries[1..count]) |start, end| {
                if (start < split and split < end) {
                    const prefix = (try it.next()).?;
                    try std.testing.expectEqual(start, prefix.start.value);
                    try std.testing.expectEqual(split, prefix.end.value);
                    try std.testing.expectError(error.EscapeInsideGrapheme, it.next());
                    try std.testing.expectError(error.EscapeInsideGrapheme, it.next());
                    rejected = true;
                    break;
                }
                const span = (try it.next()).?;
                try std.testing.expectEqual(start + @as(usize, if (start >= split) escape.len else 0), span.start.value);
                try std.testing.expectEqual(end + @as(usize, if (end > split) escape.len else 0), span.end.value);
            }
            if (!rejected) try std.testing.expect((try it.next()) == null);
        }
    }
}

test "tokens preserve source order and classify SGR without executing commands" {
    const bytes = "\x1b[31me\u{0301}\x1b[2C\x1b]0;title\x07z\x1b[0m";
    var it = zunic.terminal(bytes).tokens().iterator();
    const first = (try it.next()).?.escape;
    try std.testing.expectEqual(.sgr, first.kind);
    try std.testing.expectEqualStrings("\x1b[31m", bytes[first.span.start.value..first.span.end.value]);
    const content = (try it.next()).?.grapheme;
    try std.testing.expectEqualStrings("e\u{0301}", bytes[content.start.value..content.end.value]);
    try std.testing.expectEqual(.other, (try it.next()).?.escape.kind);
    try std.testing.expectEqual(.other, (try it.next()).?.escape.kind);
    _ = (try it.next()).?.grapheme;
    try std.testing.expectEqual(.sgr, (try it.next()).?.escape.kind);
    try std.testing.expect((try it.next()) == null);
    try std.testing.expect((try it.next()) == null);

    const sgr = [_][]const u8{ "\x1b[m", "\x1b[0m", "\x1b[38:2::1:2:3m", "\x1b[1;31m" };
    for (sgr) |bytes_| {
        var tokens = zunic.terminal(bytes_).tokens().iterator();
        try std.testing.expectEqual(.sgr, (try tokens.next()).?.escape.kind);
        try std.testing.expect((try tokens.next()) == null);
    }
    const other = [_][]const u8{ "\x1b[?1m", "\x1b[>4m", "\x1b[1 m", "\x1b]8;;url\x1b\\" };
    for (other) |bytes_| {
        var tokens = zunic.terminal(bytes_).tokens().iterator();
        try std.testing.expectEqual(.other, (try tokens.next()).?.escape.kind);
    }
}

test "token spans partition successful input" {
    const inputs = [_][]const u8{
        "",
        "plain café",
        "\x1b[31m\x1b[0m",
        "a\x1b[31mb\x1b[0m",
        "\x1b]8;;url\x1b\\link\x1b]8;;\x1b\\",
        "\xff\x1b[0m!",
        "\x1b]broken\n",
    };
    for (inputs) |bytes| {
        // Substring offsets and independent iterators are checked too.
        var tokens = zunic.terminal(bytes).tokens().iterator();
        var offset: usize = 0;
        while (try tokens.next()) |token| {
            const span = switch (token) {
                .grapheme => |span| span,
                .escape => |escape| escape.span,
            };
            try std.testing.expectEqual(offset, span.start.value);
            try std.testing.expect(span.end.value > offset);
            offset = span.end.value;
        }
        try std.testing.expectEqual(bytes.len, offset);
    }
}

test "tokens return content and each escape before a later joining scalar fails" {
    const bytes = "prefixe\x1b[31m\x1b[0m\u{0301}";
    var it = zunic.terminal(bytes[6..]).tokens().iterator();
    const prefix = (try it.next()).?.grapheme;
    try std.testing.expectEqual(@as(usize, 0), prefix.start.value);
    try std.testing.expectEqual(@as(usize, 1), prefix.end.value);
    _ = (try it.next()).?.escape;
    var copy = it;
    try std.testing.expectEqualDeep(try it.next(), try copy.next());
    try std.testing.expectError(error.EscapeInsideGrapheme, it.next());
    try std.testing.expectError(error.EscapeInsideGrapheme, copy.next());
    try std.testing.expectError(error.EscapeInsideGrapheme, it.next());
}
