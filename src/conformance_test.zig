const std = @import("std");
const unicode = @import("root.zig");

const fixture = @embedFile("data/GraphemeBreakTest-16.0.0.txt");

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
        var it = unicode.grapheme.iterator(bytes[0..len]);
        while (it.next()) |span| {
            actual[actual_len] = span.start;
            actual_len += 1;
        }
        actual[actual_len] = len;
        actual_len += 1;
        try std.testing.expectEqualSlices(usize, expected[0..expected_len], actual[0..actual_len]);
    }
}
