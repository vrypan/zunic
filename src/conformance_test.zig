const std = @import("std");
const unicode = @import("root.zig");
const grapheme = @import("grapheme.zig");

const fixture = @embedFile("data/GraphemeBreakTest-16.0.0.txt");
const line_break_fixture = @embedFile("data/LineBreakTest-16.0.0.txt");

test "Unicode 16.0.0 GraphemeBreakTest" {
    var lines = std.mem.splitScalar(u8, fixture, '\n');
    while (lines.next()) |raw_line| {
        const line = raw_line[0 .. std.mem.indexOfScalar(u8, raw_line, '#') orelse raw_line.len];
        if (std.mem.trim(u8, line, " \t\r").len == 0) continue;

        var bytes: [256]u8 = undefined;
        var expected: [64]usize = undefined;
        var len: usize = 0;
        var expected_len: usize = 0;
        var tokens = std.mem.tokenizeAny(u8, line, " \t\r");
        while (tokens.next()) |token| {
            if (std.mem.eql(u8, token, "÷")) {
                expected[expected_len] = len;
                expected_len += 1;
                continue;
            }
            if (std.mem.eql(u8, token, "×")) continue;
            const cp = std.fmt.parseInt(u21, token, 16) catch return error.TestUnexpectedResult;
            len += std.unicode.utf8Encode(cp, bytes[len..]) catch return error.TestUnexpectedResult;
        }

        var actual: [64]usize = undefined;
        var actual_len: usize = 0;
        var it = grapheme.iterator(bytes[0..len]);
        while (it.next()) |span| {
            actual[actual_len] = span.start;
            actual_len += 1;
        }
        actual[actual_len] = len;
        actual_len += 1;
        try std.testing.expectEqualSlices(usize, expected[0..expected_len], actual[0..actual_len]);
    }
}

test "Unicode 16.0.0 LineBreakTest" {
    var lines = std.mem.splitScalar(u8, line_break_fixture, '\n');
    while (lines.next()) |raw_line| {
        const line = raw_line[0 .. std.mem.indexOfScalar(u8, raw_line, '#') orelse raw_line.len];
        if (std.mem.trim(u8, line, " \t\r").len == 0) continue;

        var bytes: [512]u8 = undefined;
        var expected: [256]unicode.line_break.Boundary = undefined;
        var len: usize = 0;
        var expected_len: usize = 0;
        var tokens = std.mem.tokenizeAny(u8, line, " \t\r");
        while (tokens.next()) |token| {
            const opportunity: unicode.line_break.Opportunity = if (std.mem.eql(u8, token, "÷")) .allowed else if (std.mem.eql(u8, token, "×")) .prohibited else {
                const cp = std.fmt.parseInt(u21, token, 16) catch return error.TestUnexpectedResult;
                len += std.unicode.utf8Encode(cp, bytes[len..]) catch return error.TestUnexpectedResult;
                continue;
            };
            if (expected_len == expected.len) return error.TestUnexpectedResult;
            expected[expected_len] = .{ .offset = len, .opportunity = opportunity };
            expected_len += 1;
        }
        if (expected_len == 0) return error.TestUnexpectedResult;
        expected[expected_len - 1].opportunity = .mandatory;

        var actual: [256]unicode.line_break.Boundary = undefined;
        var actual_len: usize = 0;
        var it = unicode.line_break.iterator(bytes[0..len]);
        while (it.next()) |boundary| {
            if (actual_len == actual.len) return error.TestUnexpectedResult;
            // The fixture represents mandatory hard boundaries with the same
            // `÷` marker as ordinary allowed boundaries.  Preserve its
            // break/no-break comparison while dedicated tests pin the richer
            // mandatory result.
            actual[actual_len] = if (boundary.opportunity == .mandatory and boundary.offset != len)
                .{ .offset = boundary.offset, .opportunity = .allowed }
            else
                boundary;
            actual_len += 1;
        }
        try std.testing.expectEqualSlices(unicode.line_break.Boundary, expected[0..expected_len], actual[0..actual_len]);
    }
}

fn expectLineBreaks(bytes: []const u8, expected: []const unicode.line_break.Boundary) !void {
    var actual: [16]unicode.line_break.Boundary = undefined;
    var actual_len: usize = 0;
    var it = unicode.line_break.iterator(bytes);
    while (it.next()) |boundary| {
        actual[actual_len] = boundary;
        actual_len += 1;
    }
    try std.testing.expectEqualSlices(unicode.line_break.Boundary, expected, actual[0..actual_len]);
}

test "line-break iterator edge cases" {
    const P = unicode.line_break.Opportunity.prohibited;
    const A = unicode.line_break.Opportunity.allowed;
    const M = unicode.line_break.Opportunity.mandatory;
    try expectLineBreaks("", &.{.{ .offset = 0, .opportunity = M }});
    try expectLineBreaks("\r\n", &.{ .{ .offset = 0, .opportunity = P }, .{ .offset = 1, .opportunity = P }, .{ .offset = 2, .opportunity = M } });
    try expectLineBreaks("\xc2\x85", &.{ .{ .offset = 0, .opportunity = P }, .{ .offset = 2, .opportunity = M } });
    try expectLineBreaks("\xe2\x80\x8b  A", &.{ .{ .offset = 0, .opportunity = P }, .{ .offset = 3, .opportunity = P }, .{ .offset = 4, .opportunity = P }, .{ .offset = 5, .opportunity = A }, .{ .offset = 6, .opportunity = M } });
    try expectLineBreaks("A\xe2\x81\xa0B", &.{ .{ .offset = 0, .opportunity = P }, .{ .offset = 1, .opportunity = P }, .{ .offset = 4, .opportunity = P }, .{ .offset = 5, .opportunity = M } });
    try expectLineBreaks("A\xffB", &.{ .{ .offset = 0, .opportunity = P }, .{ .offset = 1, .opportunity = P }, .{ .offset = 2, .opportunity = P }, .{ .offset = 3, .opportunity = M } });
    try expectLineBreaks("\xf0\x9f\x87\xa6\xf0\x9f\x87\xa7\xf0\x9f\x87\xa8", &.{ .{ .offset = 0, .opportunity = P }, .{ .offset = 4, .opportunity = P }, .{ .offset = 8, .opportunity = A }, .{ .offset = 12, .opportunity = M } });
    try expectLineBreaks("\xf0\x9f\x91\x8b\xf0\x9f\x8f\xbf", &.{ .{ .offset = 0, .opportunity = P }, .{ .offset = 4, .opportunity = P }, .{ .offset = 8, .opportunity = M } });
    try expectLineBreaks("\xe0\xa4\x95\xe0\xa5\x8d\xe0\xa4\x95", &.{ .{ .offset = 0, .opportunity = P }, .{ .offset = 3, .opportunity = P }, .{ .offset = 6, .opportunity = P }, .{ .offset = 9, .opportunity = M } });
}

test "interior hard breaks are mandatory" {
    const M = unicode.line_break.Opportunity.mandatory;
    const P = unicode.line_break.Opportunity.prohibited;
    inline for ([_][]const u8{ "\n", "\r", "\r\n", "\xc2\x85", "\x0b", "\x0c", "\xe2\x80\xa8", "\xe2\x80\xa9" }) |hard| {
        var bytes: [16]u8 = undefined;
        bytes[0] = 'a';
        @memcpy(bytes[1..][0..hard.len], hard);
        bytes[hard.len + 1] = 'b';
        var it = unicode.line_break.iterator(bytes[0 .. hard.len + 2]);
        try std.testing.expectEqual(P, it.next().?.opportunity);
        _ = it.next(); // Boundaries inside CRLF are prohibited.
        var saw_mandatory = false;
        while (it.next()) |boundary| {
            if (boundary.offset == hard.len + 1 and boundary.opportunity == M) saw_mandatory = true;
        }
        try std.testing.expect(saw_mandatory);
    }
}
