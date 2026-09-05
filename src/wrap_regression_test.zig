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

test "wrap matches independent reference regressions" {
    const Case = struct { bytes: []const u8, width: usize, overflow: unicode.wrap.Overflow };
    const cases = [_]Case{
        .{ .bytes = "a bcdef", .width = 4, .overflow = .allow },
        .{ .bytes = "abc def", .width = 3, .overflow = .grapheme },
        .{ .bytes = "abc def", .width = 3, .overflow = .allow },
        .{ .bytes = "界\n", .width = 1, .overflow = .grapheme },
        .{ .bytes = "界\x00", .width = 1, .overflow = .grapheme },
        .{ .bytes = "界\n\n", .width = 1, .overflow = .grapheme },
        .{ .bytes = "longword\n", .width = 2, .overflow = .allow },
        .{ .bytes = "a\x0bb\x0cc\xc2\x85d\xe2\x80\xa8e\xe2\x80\xa9", .width = 1, .overflow = .grapheme },
        .{ .bytes = "\xff\xc0\x80 e\xcc\x81 🇬🇷👩‍👩‍👧‍👦", .width = 2, .overflow = .grapheme },
        .{ .bytes = "123,456.78 9", .width = 3, .overflow = .allow },
        .{ .bytes = "", .width = 1, .overflow = .grapheme },
    };
    for (cases) |case| try expectProductionMatchesReference(case.bytes, .{ .max_columns = case.width, .overflow = case.overflow });
}

test "wrap matches independent reference randomized" {
    const atoms = [_][]const u8{ "a", " ", "界", "\x00", "\n", "\xff", "e\xcc\x81", "🇬🇷", "👩‍👩‍👧‍👦", "1", ",", "\r\n" };
    var random = std.Random.DefaultPrng.init(0x5eed_600d);
    var buffer: [256]u8 = undefined;
    const widths = [_]usize{ 1, 2, 3, 4, 40, 80 };
    for (0..200) |_| {
        var length: usize = 0;
        const count = random.random().intRangeAtMost(usize, 0, 24);
        for (0..count) |_| {
            const atom = atoms[random.random().uintLessThan(usize, atoms.len)];
            if (length + atom.len > buffer.len) break;
            @memcpy(buffer[length..][0..atom.len], atom);
            length += atom.len;
        }
        const bytes = buffer[0..length];
        for (widths) |max_columns| {
            try expectProductionMatchesReference(bytes, .{ .max_columns = max_columns, .overflow = .grapheme });
            try expectProductionMatchesReference(bytes, .{ .max_columns = max_columns, .overflow = .allow });
        }
    }
}

test "ASCII fast path preserves word and viewport lines" {
    try expectProductionMatchesReference("abcdefghijklmnopqrstuvwxyz", .{ .max_columns = 5, .overflow = .grapheme });
    try expectProductionMatchesReference("abcdefghijklmnopqrstuvwxyz", .{ .max_columns = 5, .overflow = .allow });
    try expectProductionMatchesReference("abc\xcc\x81def", .{ .max_columns = 3, .overflow = .grapheme });
    try expectProductionMatchesReference("abc def", .{ .max_columns = 3, .overflow = .allow });
    try expectProductionMatchesReference("alpha beta gamma\r\ndelta", .{ .max_columns = 6, .overflow = .grapheme });
    try expectProductionMatchesReference("alpha beta gamma\r\ndelta", .{ .max_columns = 6, .overflow = .allow });
}
