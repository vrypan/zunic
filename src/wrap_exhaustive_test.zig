//! Opt-in exhaustive wrapping sweep: `zig build wrap-exhaustive`.
//!
//! Same differential check as the regression suite, over the full ASCII
//! fast-path alphabet including 0x0B and 0x0C (line-break class BK, which
//! `\n` (LF) and `\r` (CR) do not represent). Kept out of `zig build test`
//! because the wider alphabet multiplies the sweep by roughly three.
const std = @import("std");
const unicode = @import("zunic");
const reference = @import("wrap_reference.zig");

fn expectProductionMatchesReference(bytes: []const u8, options: unicode.wrap.Options) !void {
    const expected = try reference.collect(std.testing.allocator, bytes, options);
    defer std.testing.allocator.free(expected);

    var actual = try unicode.wrap.iterator(bytes, options);
    for (expected) |want| {
        const got = actual.next() orelse return error.TestUnexpectedResult;
        if (!std.meta.eql(want, got)) std.debug.print("wrap mismatch bytes={s} width={d} overflow={s} want={any} got={any}\n", .{ bytes, options.max_columns, @tagName(options.overflow), want, got });
        try std.testing.expectEqualDeep(want, got);
    }
    try std.testing.expect(actual.next() == null);
    try std.testing.expect(actual.next() == null);
}

test "ASCII paragraph fast path matches reference over the full alphabet" {
    const alphabet = [_]u8{ 'a', 'Z', '7', '\'', ' ', '\n', '\r', 0x0B, 0x0C };
    var buffer: [5]u8 = undefined;
    for (0..6) |length| {
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
