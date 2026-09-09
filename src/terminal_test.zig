const std = @import("std");
const zunic = @import("zunic");

fn expectSpans(bytes: []const u8, expected: []const []const u8) !void {
    var it = zunic.terminal(bytes).graphemes().iterator();
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

test "escapes inside graphemes fail before returning the affected cluster" {
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
        var it = zunic.terminal(bytes).graphemes().iterator();
        try std.testing.expectError(error.EscapeInsideGrapheme, it.next());
        try std.testing.expectError(error.EscapeInsideGrapheme, it.next());
        var copy = it;
        try std.testing.expectError(error.EscapeInsideGrapheme, copy.next());
    }
    var it = zunic.terminal("ae\x1b[31m\u{0301}z").graphemes().iterator();
    const first = (try it.next()).?;
    try std.testing.expectEqual(@as(usize, 0), first.start.value);
    try std.testing.expectEqual(@as(usize, 1), first.end.value);
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
        var terminal = zunic.terminal(bytes).graphemes().iterator();
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
    var it = view.graphemes().iterator();
    const first = (try it.next()).?;
    try std.testing.expectEqual(@as(usize, 5), first.start.value);
    try std.testing.expectEqual(@as(usize, 6), first.end.value);
    var copy = it;
    try std.testing.expectEqualDeep((try it.next()), (try copy.next()));
    try std.testing.expect((try it.next()) == null);
    try std.testing.expect((try copy.next()) == null);
    var fresh = view.graphemes().iterator();
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
            var it = zunic.terminal(decorated[0 .. len + escape.len]).graphemes().iterator();
            var rejected = false;
            for (boundaries[0 .. count - 1], boundaries[1..count]) |start, end| {
                if (start < split and split < end) {
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
