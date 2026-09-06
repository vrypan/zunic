//! Opt-in exhaustive wrapping sweep: `zig build wrap-exhaustive`.
//!
//! Same differential check as the regression suite, over the whole ASCII
//! fast-path alphabet: every accepted punctuation character, plus 0x0B and
//! 0x0C (line-break class BK, which `\n` (LF) and `\r` (CR) do not
//! represent). Kept out of `zig build test` because 20 characters make the
//! sweep far too slow for the default suite; the depth is reduced to 4 to
//! keep even this run tractable.
const std = @import("std");
const unicode = @import("zunic");
const reference = @import("wrap_reference.zig");

fn expectProductionMatchesReference(bytes: []const u8, options: unicode.WrapOptions) !void {
    const expected = try reference.collect(std.testing.allocator, bytes, options);
    defer std.testing.allocator.free(expected);

    var actual = (try unicode.wrap(bytes, options)).iterator();
    for (expected) |want| {
        const got = actual.next() orelse return error.TestUnexpectedResult;
        try std.testing.expectEqual(want.start, got.start.value);
        try std.testing.expectEqual(want.end, got.end.value);
        try std.testing.expectEqual(want.columns, got.columns.value);
    }
    try std.testing.expect(actual.next() == null);
    try std.testing.expect(actual.next() == null);
}

test "ASCII paragraph fast path matches reference over the full alphabet" {
    const alphabet = [_]u8{
        'a', 'Z', '7', ' ', '\n', '\r', 0x0B, 0x0C,
        '.', ',', ';', ':', '\'', '"',  '#',  '&',
        '*', '=', '@', '_',
    };
    var buffer: [4]u8 = undefined;
    for (0..5) |length| {
        const combinations = std.math.pow(usize, alphabet.len, length);
        for (0..combinations) |value| {
            var remaining = value;
            for (0..length) |index| {
                buffer[index] = alphabet[remaining % alphabet.len];
                remaining /= alphabet.len;
            }
            for ([_]usize{ 1, 2, 3 }) |max_columns| {
                try expectProductionMatchesReference(buffer[0..length], .{ .max_columns = max_columns, .overflow = .grapheme });
                try expectProductionMatchesReference(buffer[0..length], .{ .max_columns = max_columns, .overflow = .allow });
            }
        }
    }
}
