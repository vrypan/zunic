//! Opt-in exhaustive wrapping sweep: `zig build wrap-exhaustive`.
//!
//! Same differential check as the regression suite, driven from one
//! representative per distinct UAX #14 class rather than from the ASCII
//! fast-path alphabet alone. Bytes inside that alphabet exercise the fast
//! path; bytes outside it demote the input to the general path, so the sweep
//! spans both and keeps covering whichever bytes the alphabet admits.
//!
//! It is built this way because the previous version enumerated exactly the
//! accepted alphabet and therefore could not see any byte a widening would
//! add. Plan 020's spike widened the alphabet and this sweep, in that order,
//! and the wider sweep immediately found two defects the narrow one passed:
//! a hyphen after a space (UAX #14 LB20a) and a zero-column byte on an
//! already-overflowing line. Both were in the spike, which was rejected on
//! performance and reverted; the coverage is kept so a future attempt cannot
//! reintroduce them silently.
//!
//! Kept out of `zig build test` because the sweep is far too slow for the
//! default suite; the depth is 4 to keep even this run tractable.
const std = @import("std");
const unicode = @import("zunic");
const reference = @import("wrap_reference.zig");

fn expectProductionMatchesReference(bytes: []const u8, options: unicode.WrapOptions) !void {
    const expected = try reference.collect(std.testing.allocator, bytes, options);
    defer std.testing.allocator.free(expected);

    var actual = (try unicode.text(bytes).wrap(options)).iterator();
    for (expected) |want| {
        const got = actual.next() orelse return error.TestUnexpectedResult;
        try std.testing.expectEqual(want.start, got.start.value);
        try std.testing.expectEqual(want.end, got.end.value);
        try std.testing.expectEqual(want.columns, got.columns.value);
    }
    try std.testing.expect(actual.next() == null);
    try std.testing.expect(actual.next() == null);
}

test "wrapping matches the reference across UAX #14 class representatives" {
    const alphabet = [_]u8{
        // AL, NU, SP and the hard terminators.
        'a', 'Z', '7', ' ',  '\n', '\r', 0x0B, 0x0C,
        // IS, QU, and an AL punctuation representative.
        '.', ',', '"', '\'', '_',
        // Classes the fast-path alphabet does not admit today, so these
        // combinations run the general path: BA-hyphen, OP, CP, SY, EX, PO,
        // PR, and tab -- the one byte that measures zero columns.
         '-',  '(',  ')',
        '/', '!', '%', '$',  0x09,
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
