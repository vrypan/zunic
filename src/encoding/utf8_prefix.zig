//! Strict classification of a UTF-8 scalar prefix.

pub const Classification = union(enum) {
    invalid,
    incomplete: usize,
    complete: usize,
};

/// Classify one non-empty prefix without inspecting more than four bytes.
/// `incomplete` names the next prefix length needed to decide the scalar.
pub fn classify(bytes: []const u8) Classification {
    if (bytes.len == 0 or bytes.len > 4) return .invalid;

    const lead = bytes[0];
    const length: usize = if (lead < 0x80)
        1
    else if (lead >= 0xc2 and lead <= 0xdf)
        2
    else if (lead >= 0xe0 and lead <= 0xef)
        3
    else if (lead >= 0xf0 and lead <= 0xf4)
        4
    else
        return .invalid;

    if (length == 1) return .{ .complete = 1 };
    if (bytes.len == 1) return .{ .incomplete = 2 };

    const second = bytes[1];
    if (!continuation(second) or
        (lead == 0xe0 and second < 0xa0) or
        (lead == 0xed and second > 0x9f) or
        (lead == 0xf0 and second < 0x90) or
        (lead == 0xf4 and second > 0x8f)) return .invalid;

    if (length == 2) return .{ .complete = 2 };
    if (bytes.len == 2) return .{ .incomplete = 3 };
    if (!continuation(bytes[2])) return .invalid;

    if (length == 3) return .{ .complete = 3 };
    if (bytes.len == 3) return .{ .incomplete = 4 };
    if (!continuation(bytes[3])) return .invalid;
    return .{ .complete = 4 };
}

inline fn continuation(byte: u8) bool {
    return byte & 0xc0 == 0x80;
}

test "completed prefixes agree with the standard library" {
    const std = @import("std");
    var encoded: [4]u8 = undefined;
    for (0..0x110000) |value| {
        if (value >= 0xd800 and value <= 0xdfff) continue;
        const cp: u21 = @intCast(value);
        const len = try std.unicode.utf8Encode(cp, &encoded);
        for (1..len) |prefix_len| {
            try std.testing.expectEqual(Classification{ .incomplete = prefix_len + 1 }, classify(encoded[0..prefix_len]));
        }
        try std.testing.expectEqual(Classification{ .complete = len }, classify(encoded[0..len]));
        try std.testing.expectEqual(cp, try std.unicode.utf8Decode(encoded[0..len]));
    }
}

test "invalid prefixes are rejected as soon as provable" {
    const std = @import("std");
    const invalid = [_][]const u8{
        "\x80",          "\xbf",     "\xc0",     "\xc1",     "\xf5",     "\xff",
        "\xc2A",         "\xe0\x80", "\xed\xa0", "\xf0\x80", "\xf4\x90", "\xe2\x82A",
        "\xf0\x9f\x91A",
    };
    for (invalid) |bytes| try std.testing.expectEqual(Classification.invalid, classify(bytes));
}
