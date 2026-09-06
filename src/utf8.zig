//! Loss-tolerant UTF-8 stepping. Invalid input consumes exactly one byte.
const std = @import("std");

pub const Step = struct {
    len: usize,
    cp: ?u21,
};

pub inline fn step(bytes: []const u8) Step {
    if (bytes.len == 0) return .{ .len = 0, .cp = null };
    const b0 = bytes[0];
    if (b0 < 0x80) return .{ .len = 1, .cp = b0 };
    if (b0 >= 0xc2 and b0 <= 0xdf) {
        if (bytes.len < 2 or !continuation(bytes[1])) return invalid();
        return .{ .len = 2, .cp = (@as(u21, b0 & 0x1f) << 6) | (bytes[1] & 0x3f) };
    }
    if (b0 >= 0xe0 and b0 <= 0xef) {
        if (bytes.len < 3) return invalid();
        const b1 = bytes[1];
        const b2 = bytes[2];
        if (!continuation(b1) or !continuation(b2) or
            (b0 == 0xe0 and b1 < 0xa0) or (b0 == 0xed and b1 >= 0xa0)) return invalid();
        return .{ .len = 3, .cp = (@as(u21, b0 & 0x0f) << 12) | (@as(u21, b1 & 0x3f) << 6) | (b2 & 0x3f) };
    }
    if (b0 >= 0xf0 and b0 <= 0xf4) {
        if (bytes.len < 4) return invalid();
        const b1 = bytes[1];
        const b2 = bytes[2];
        const b3 = bytes[3];
        if (!continuation(b1) or !continuation(b2) or !continuation(b3) or
            (b0 == 0xf0 and b1 < 0x90) or (b0 == 0xf4 and b1 >= 0x90)) return invalid();
        return .{ .len = 4, .cp = (@as(u21, b0 & 0x07) << 18) | (@as(u21, b1 & 0x3f) << 12) | (@as(u21, b2 & 0x3f) << 6) | (b3 & 0x3f) };
    }
    return invalid();
}

inline fn continuation(byte: u8) bool {
    return byte & 0xc0 == 0x80;
}

inline fn invalid() Step {
    return .{ .len = 1, .cp = null };
}

fn reference(bytes: []const u8) Step {
    if (bytes.len == 0) return .{ .len = 0, .cp = null };
    const len = std.unicode.utf8ByteSequenceLength(bytes[0]) catch return invalid();
    if (len > bytes.len) return invalid();
    const cp = std.unicode.utf8Decode(bytes[0..len]) catch return invalid();
    return .{ .len = len, .cp = cp };
}

test "explicit decoder matches standard-library tolerant reference" {
    var encoded: [4]u8 = undefined;
    for (0..0x110000) |value| {
        if (value >= 0xd800 and value <= 0xdfff) continue;
        const cp: u21 = @intCast(value);
        const len = try std.unicode.utf8Encode(cp, &encoded);
        try std.testing.expectEqualDeep(reference(encoded[0..len]), step(encoded[0..len]));
        for (0..len) |truncated| try std.testing.expectEqualDeep(reference(encoded[0..truncated]), step(encoded[0..truncated]));
    }
    for (0..256) |leading| {
        const bytes = [_]u8{ @intCast(leading), 0x80, 0x80, 0x80 };
        for (1..5) |len| try std.testing.expectEqualDeep(reference(bytes[0..len]), step(bytes[0..len]));
    }
    const invalids = [_][]const u8{
        "\x80a",             "\xbfa",             "\xc0\x80a",         "\xc1\xbfa", "\xe0\x80\x80a", "\xed\xa0\x80a",
        "\xf0\x80\x80\x80a", "\xf4\x90\x80\x80a", "\xf5\x80\x80\x80a", "\xffa",     "\xc2A",         "\xe2\x82A",
        "\xf0\x9f\x91A",     "ok\xffvalid",
    };
    for (invalids) |bytes| {
        var pos: usize = 0;
        while (pos < bytes.len) {
            const actual = step(bytes[pos..]);
            try std.testing.expectEqualDeep(reference(bytes[pos..]), actual);
            try std.testing.expect(actual.len >= 1);
            pos += actual.len;
        }
        try std.testing.expectEqual(bytes.len, pos);
    }
    var random = std.Random.DefaultPrng.init(0x016_dec0de);
    for (0..200_000) |_| {
        random.fill(&encoded);
        const len = random.random().intRangeAtMost(usize, 0, 4);
        try std.testing.expectEqualDeep(reference(encoded[0..len]), step(encoded[0..len]));
    }
}
