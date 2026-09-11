const std = @import("std");
const zunic = @import("zunic");

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

test "escape after repeated ZWJs precedes a new emoji grapheme" {
    const prefix = "\u{1F600}\u{200D}\u{200D}";
    const emoji = "\u{1F600}";
    try expectSpans(prefix ++ "\x1b[31m" ++ emoji, &.{ prefix, emoji });
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
    try std.testing.expectEqual(.sgr, std.meta.activeTag(first.effect));
    try std.testing.expectEqualStrings("\x1b[31m", bytes[first.span.start.value..first.span.end.value]);
    const content = (try it.next()).?.grapheme;
    try std.testing.expectEqualStrings("e\u{0301}", bytes[content.start.value..content.end.value]);
    try std.testing.expectEqual(.other, std.meta.activeTag((try it.next()).?.escape.effect));
    try std.testing.expectEqual(.other, std.meta.activeTag((try it.next()).?.escape.effect));
    _ = (try it.next()).?.grapheme;
    try std.testing.expectEqual(.sgr, std.meta.activeTag((try it.next()).?.escape.effect));
    try std.testing.expect((try it.next()) == null);
    try std.testing.expect((try it.next()) == null);

    const sgr = [_][]const u8{ "\x1b[m", "\x1b[0m", "\x1b[38:2::1:2:3m", "\x1b[1;31m" };
    for (sgr) |bytes_| {
        var tokens = zunic.terminal(bytes_).tokens().iterator();
        try std.testing.expectEqual(.sgr, std.meta.activeTag((try tokens.next()).?.escape.effect));
        try std.testing.expect((try tokens.next()) == null);
    }
    const other = [_][]const u8{
        "\x1b[?1m",
        "\x1b[>4m",
        "\x1b[1 m",
    };
    for (other) |bytes_| {
        var tokens = zunic.terminal(bytes_).tokens().iterator();
        try std.testing.expectEqual(.other, std.meta.activeTag((try tokens.next()).?.escape.effect));
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

fn stateAfter(bytes: []const u8) !zunic.TerminalState {
    var it = zunic.terminal(bytes).tokens().iterator();
    while (try it.next()) |_| {}
    return it.state;
}

test "formatting state follows returned tokens and survives errors and copies" {
    var it = zunic.terminal("e\x1b[1;31m\u{0301}").tokens().iterator();
    try std.testing.expectEqualDeep(zunic.TerminalState{}, it.state);
    _ = (try it.next()).?.grapheme;
    try std.testing.expectEqualDeep(zunic.TerminalState{}, it.state);
    _ = (try it.next()).?.escape;
    try std.testing.expect(it.state.bold);
    try std.testing.expectEqual(@as(u8, 1), it.state.foreground.indexed);
    var copy = it;
    const saved = it.state;
    try std.testing.expectError(error.EscapeInsideGrapheme, it.next());
    try std.testing.expectError(error.EscapeInsideGrapheme, it.next());
    try std.testing.expectError(error.EscapeInsideGrapheme, copy.next());
    try std.testing.expectEqualDeep(saved, it.state);
    try std.testing.expectEqualDeep(saved, copy.state);

    var normal = zunic.terminal("\x1b[31ma\x1b[0m").tokens().iterator();
    _ = try normal.next();
    var independent = normal;
    _ = try normal.next();
    try std.testing.expectEqualDeep(normal.state, independent.state);
    _ = try normal.next();
    try std.testing.expectEqualDeep(zunic.TerminalState{}, normal.state);
    try std.testing.expectEqual(@as(u8, 1), independent.state.foreground.indexed);
    _ = try independent.next();
    _ = try independent.next();
    try std.testing.expectEqualDeep(normal.state, independent.state);
    try std.testing.expect((try normal.next()) == null);
    try std.testing.expect((try normal.next()) == null);
    try std.testing.expectEqualDeep(zunic.TerminalState{}, normal.state);
}

test "SGR attributes and selective resets" {
    const on = "\x1b[1;2;3;4;6;7;8;9;19;20;26;52;53;60;61;62;63;64;74m";
    const active = try stateAfter(on);
    try std.testing.expect(active.bold and active.faint and active.italic and active.fraktur);
    try std.testing.expect(active.inverse and active.concealed and active.strikethrough);
    try std.testing.expect(active.proportional and active.overline);
    try std.testing.expectEqual(.single, active.underline);
    try std.testing.expectEqual(.rapid, active.blink);
    try std.testing.expectEqual(.alternate_9, active.font);
    try std.testing.expectEqual(.encircled, active.frame);
    try std.testing.expectEqual(.subscript, active.script);
    try std.testing.expectEqualDeep(zunic.TerminalState.Ideogram{
        .underline = true,
        .double_underline = true,
        .overline = true,
        .double_overline = true,
        .stress = true,
    }, active.ideogram);
    try std.testing.expectEqualDeep(zunic.TerminalState{}, try stateAfter(on ++ "\x1b[22;23;24;25;27;28;29;10;50;54;55;65;75m"));
    try std.testing.expectEqualDeep(zunic.TerminalState{}, try stateAfter(on ++ "\x1b[m"));
    try std.testing.expectEqualDeep(zunic.TerminalState{}, try stateAfter(on ++ "\x1b[0m"));
    const order = try stateAfter("\x1b[1;0;3m");
    try std.testing.expectEqualDeep(zunic.TerminalState{ .italic = true }, order);
    try std.testing.expectEqualDeep(zunic.TerminalState{ .italic = true }, try stateAfter("\x1b[1;;3m"));
    try std.testing.expectEqual(.double, (try stateAfter("\x1b[21m")).underline);
    try std.testing.expectEqual(.slow, (try stateAfter("\x1b[5m")).blink);
    try std.testing.expectEqual(.framed, (try stateAfter("\x1b[51m")).frame);
    try std.testing.expectEqual(.superscript, (try stateAfter("\x1b[73m")).script);
}

test "SGR colors preserve palette references and support semicolon and colon RGB" {
    const Color = zunic.TerminalState.Color;
    const basic = try stateAfter("\x1b[31;104m");
    try std.testing.expectEqualDeep(Color{ .indexed = 1 }, basic.foreground);
    try std.testing.expectEqualDeep(Color{ .indexed = 12 }, basic.background);
    const other = try stateAfter("\x1b[97;40m");
    try std.testing.expectEqualDeep(Color{ .indexed = 15 }, other.foreground);
    try std.testing.expectEqualDeep(Color{ .indexed = 0 }, other.background);
    const colors = try stateAfter("\x1b[38;5;255;48;2;12;34;56;58:5:7m");
    try std.testing.expectEqualDeep(Color{ .indexed = 255 }, colors.foreground);
    try std.testing.expectEqualDeep(Color{ .rgb = .{ .r = 12, .g = 34, .b = 56 } }, colors.background);
    try std.testing.expectEqualDeep(Color{ .indexed = 7 }, colors.underline_color);
    const rgb = Color{ .rgb = .{ .r = 1, .g = 2, .b = 3 } };
    for ([_][]const u8{ "\x1b[38:2:1:2:3m", "\x1b[38:2::1:2:3m", "\x1b[38:2:0:1:2:3m" }) |input| {
        try std.testing.expectEqualDeep(rgb, (try stateAfter(input)).foreground);
    }
    try std.testing.expectEqualDeep(rgb, (try stateAfter("\x1b[48:2::1:2:3m")).background);
    try std.testing.expectEqualDeep(rgb, (try stateAfter("\x1b[58;2;1;2;3m")).underline_color);
    try std.testing.expectEqualDeep(zunic.TerminalState{}, try stateAfter("\x1b[31;42;58;5;8m\x1b[39;49;59m"));
    for (0..6) |style| {
        var bytes = "\x1b[4:0m".*;
        bytes[4] += @intCast(style);
        try std.testing.expectEqual(@as(zunic.TerminalState.Underline, @enumFromInt(style)), (try stateAfter(&bytes)).underline);
    }
}

test "unknown and invalid SGR parameters do not become unintended attributes" {
    const inputs = [_][]const u8{
        "\x1b[999999999999999999999999999m", "\x1b[999m",
        "\x1b[4:99m",                        "\x1b[1:2m",
        "\x1b[4:3:1m",                       "\x1b[38;2;999;1;2m",
        "\x1b[38;5;256m",                    "\x1b[38;5;m",
        "\x1b[38;2;1;2m",                    "\x1b[38;99;1m",
        "\x1b[38;2;1;;3m",                   "\x1b[38:2:1:1:2:3m",
        "\x1b[38:2::1:2:3:4m",               "\x1b[38:5:1:2m",
        "\x1b[?1m",                          "\x1b]0;title\x07",
        "\x1b[2J",                           "\x1b[31",
    };
    for (inputs) |input| {
        try std.testing.expectEqualDeep(zunic.TerminalState{}, try stateAfter(input));
    }
    try std.testing.expect((try stateAfter("\x1b[999;1m")).bold);
    try std.testing.expect((try stateAfter("\x1b[38;2;999;1;2;3m")).italic);
    try std.testing.expect((try stateAfter("\x1b[38:2::999:1:2;3m")).italic);
}

test "OSC 8 links borrow full parameters and URI and outlive SGR resets" {
    const input = "prefix\x1b]8;id=abc:custom=yes;https://example.com/a;b\x1b\\x\x1b[31m\x1b[0m\x1b]8;;\x07";
    const bytes = input[6..];
    var it = zunic.terminal(bytes).tokens().iterator();
    try std.testing.expect(it.state.link == null);
    try std.testing.expectEqual(.hyperlink, std.meta.activeTag((try it.next()).?.escape.effect));
    const link = it.state.link.?;
    try std.testing.expectEqualStrings("id=abc:custom=yes", link.params);
    try std.testing.expectEqualStrings("https://example.com/a;b", link.uri);
    try std.testing.expect(link.params.ptr == bytes[4..].ptr);
    var copy = it;
    _ = (try it.next()).?.grapheme;
    _ = (try it.next()).?.escape;
    _ = (try it.next()).?.escape;
    try std.testing.expectEqualDeep(zunic.TerminalState{ .link = link }, it.state);
    _ = (try it.next()).?.escape;
    try std.testing.expectEqualDeep(zunic.TerminalState{}, it.state);
    try std.testing.expectEqualDeep(link, copy.state.link.?);
    _ = try copy.next();
    try std.testing.expectEqualStrings("new", (try stateAfter("\x1b]8;;old\x07\x1b]8;id=b;new\x07")).link.?.uri);
    try std.testing.expect((try stateAfter("\x1b]8;;url\x07\x1b]8;id=b;\x1b\\")).link == null);
    try std.testing.expectEqualStrings("url", (try stateAfter("\x1b]8;;url\x07\x1b]8;broken\x07")).link.?.uri);
    try std.testing.expectEqualStrings("url", (try stateAfter("\x1b]8;;url\x07\x1b]0;title\x07")).link.?.uri);
}

fn sgrFields(bytes: []const u8) !zunic.StyleFields {
    var it = zunic.terminal(bytes).tokens().iterator();
    return (try it.next()).?.escape.effect.sgr;
}

test "SGR effects report assignments including repeated values and selective resets" {
    const expected = zunic.StyleFields{ .bold = true, .foreground = true };
    var it = zunic.terminal("\x1b[1;31m\x1b[1;31m").tokens().iterator();
    try std.testing.expectEqualDeep(expected, (try it.next()).?.escape.effect.sgr);
    const state = it.state;
    try std.testing.expectEqualDeep(expected, (try it.next()).?.escape.effect.sgr);
    try std.testing.expectEqualDeep(state, it.state);
    try std.testing.expectEqualDeep(zunic.StyleFields{ .bold = true, .faint = true }, try sgrFields("\x1b[22m"));
    try std.testing.expectEqualDeep(zunic.StyleFields{ .italic = true, .fraktur = true }, try sgrFields("\x1b[23m"));
    try std.testing.expectEqualDeep(zunic.StyleFields{ .underline = true, .underline_color = true }, try sgrFields("\x1b[4:3;58:2::1:2:3m"));
    try std.testing.expectEqualDeep(zunic.StyleFields{ .background = true }, try sgrFields("\x1b[48;5;2m"));
    try std.testing.expectEqualDeep(zunic.StyleFields{ .ideogram = true }, try sgrFields("\x1b[60;65m"));
    const all = try sgrFields("\x1b[0m");
    inline for (@typeInfo(zunic.StyleFields).@"struct".fields) |field| {
        try std.testing.expectEqual(!std.mem.eql(u8, field.name, "unhandled"), @field(all, field.name));
    }
    try std.testing.expectEqualDeep(all, try sgrFields("\x1b[m"));
    try std.testing.expectEqualDeep(all, try sgrFields("\x1b[1;;31m"));
}

test "SGR effects retain handled fields while reporting unhandled parameters" {
    for ([_][]const u8{
        "\x1b[999m",           "\x1b[99999999999999999999999m", "\x1b[4:99m",
        "\x1b[4:3:1m",         "\x1b[38m",                      "\x1b[38;5m",
        "\x1b[38;5;999m",      "\x1b[38;2;1;2m",                "\x1b[38;2;1;2;999m",
        "\x1b[38:2::1:2:999m", "\x1b[38:2:1:1:2:3m",            "\x1b[38:5:2:3m",
        "\x1b[38;99;1m",       "\x1b[38:2m",                    "\x1b[38:9m",
        "\x1b[1:2m",
    }) |input| {
        try std.testing.expectEqualDeep(zunic.StyleFields{ .unhandled = true }, try sgrFields(input));
    }
    try std.testing.expectEqualDeep(zunic.StyleFields{ .bold = true, .unhandled = true }, try sgrFields("\x1b[1;38;2;1m"));
    try std.testing.expectEqualDeep(zunic.StyleFields{ .italic = true, .unhandled = true }, try sgrFields("\x1b[38;2;999;1;2;3m"));
    try std.testing.expectEqualDeep(zunic.StyleFields{ .foreground = true, .unhandled = true }, try sgrFields("\x1b[31;38;5;999m"));
    try std.testing.expectEqualDeep(zunic.StyleFields{ .bold = true, .foreground = true, .unhandled = true }, try sgrFields("\x1b[1;999;31m"));
    var all = try sgrFields("\x1b[0m");
    all.unhandled = true;
    try std.testing.expectEqualDeep(all, try sgrFields("\x1b[999;0m"));
    try std.testing.expectEqualDeep(all, try sgrFields("\x1b[0;999m"));
    var it = zunic.terminal("\x1b[999m\x1b[31m").tokens().iterator();
    try std.testing.expect((try it.next()).?.escape.effect.sgr.unhandled);
    try std.testing.expect(!(try it.next()).?.escape.effect.sgr.unhandled);
}

test "hyperlink effects distinguish link updates from other OSC and CSI" {
    const bytes = "\x1b]8;;url\x07\x1b]8;broken\x07\x1b]0;title\x07\x1b[2J\x1b]8;;\x1b\\";
    var it = zunic.terminal(bytes).tokens().iterator();
    try std.testing.expectEqual(.hyperlink, std.meta.activeTag((try it.next()).?.escape.effect));
    try std.testing.expectEqualStrings("url", it.state.link.?.uri);
    for (0..3) |_| {
        try std.testing.expectEqual(.other, std.meta.activeTag((try it.next()).?.escape.effect));
        try std.testing.expectEqualStrings("url", it.state.link.?.uri);
    }
    try std.testing.expectEqual(.hyperlink, std.meta.activeTag((try it.next()).?.escape.effect));
    try std.testing.expect(it.state.link == null);
}
