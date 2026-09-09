const std = @import("std");
const strip = @import("strip.zig");

test "stripAnsi block copies preserve alignment, overlap and partial prefixes" {
    const escape = "\x1b[31m";
    for (0..32) |alignment| {
        for ([_]usize{ 0, 1, 15, 16, 17, 31, 32, 33, 63, 64, 65, 127 }) |run_len| {
            var storage: [384]u8 = @splat(0xa5);
            const len = run_len * 2 + escape.len;
            const input = storage[alignment..][0..len];
            @memset(input[0..run_len], 0xff);
            @memcpy(input[run_len..][0..escape.len], escape);
            @memset(input[run_len + escape.len ..], 'x');
            var expected: [254]u8 = undefined;
            @memset(expected[0..run_len], 0xff);
            @memset(expected[run_len..][0..run_len], 'x');
            const output_len = run_len * 2;
            // Include shortages in either run, exact fits, and spare capacity.
            for ([_]usize{ 0, run_len, output_len -| 1, output_len, output_len + 1 }) |capacity| {
                var output: [384]u8 = @splat(0xa5);
                const buffer = output[alignment..][0..capacity];
                if (capacity < output_len) {
                    try std.testing.expectError(error.NoSpace, strip.stripAnsi(input, buffer));
                    try std.testing.expectEqualSlices(u8, expected[0..capacity], buffer);
                } else {
                    try std.testing.expectEqualSlices(u8, expected[0..output_len], try strip.stripAnsi(input, buffer));
                }
                try std.testing.expectEqual(@as(u8, 0xa5), output[alignment + @min(capacity, output_len)]);
                var inplace = storage;
                const same = inplace[alignment..][0..len];
                if (capacity < output_len) {
                    try std.testing.expectError(error.NoSpace, strip.stripAnsi(same, same[0..capacity]));
                    try std.testing.expectEqualSlices(u8, expected[0..capacity], same[0..capacity]);
                } else {
                    try std.testing.expectEqualSlices(u8, expected[0..output_len], try strip.stripAnsi(same, same));
                }
            }
        }
    }
}

test "stripAnsi removes commands without interpreting content" {
    const cases = [_]struct { input: []const u8, output: []const u8 }{
        .{ .input = "", .output = "" },
        .{ .input = "plain\r\n\t\x00\xff", .output = "plain\r\n\t\x00\xff" },
        .{ .input = "\x1b[31mred\x1b[0m", .output = "red" },
        .{ .input = "e\x1b[31m\u{0301}", .output = "e\u{0301}" },
        .{ .input = "\xc3\x1b[0m\xa9", .output = "\xc3\xa9" },
        .{ .input = "\xff\x1b[2C\xfe\x1b]0;\xff\x07!", .output = "\xff\xfe!" },
        .{ .input = "\x1b]8;;url\x1b\\link\x1b]8;;\x1b\\", .output = "link" },
        .{ .input = "\x1b[31m\x1b]0;title\x07", .output = "" },
        .{ .input = "\x1b[31", .output = "\x1b[31" },
        .{ .input = "\x1b]broken\n", .output = "\x1b]broken\n" },
        .{ .input = "\x1bPother\x1b\\", .output = "\x1bPother\x1b\\" },
        .{ .input = "\x1b]\x1b[0mx", .output = "\x1b]x" },
    };
    for (cases) |case| {
        var buffer: [128]u8 = @splat(0xa5);
        const result = try strip.stripAnsi(case.input, buffer[0..case.output.len]);
        try std.testing.expectEqualStrings(case.output, result);
        try std.testing.expectEqual(@intFromPtr(&buffer), @intFromPtr(result.ptr));
        try std.testing.expectEqual(@as(u8, 0xa5), buffer[result.len]); // No terminator.
    }
    // Every isolated byte is retained, including malformed UTF-8 and controls.
    for (0..256) |byte| {
        const input = [_]u8{@intCast(byte)};
        var output: [1]u8 = undefined;
        try std.testing.expectEqualSlices(u8, &input, try strip.stripAnsi(&input, &output));
    }
}

test "stripAnsi capacity, partial writes and in-place compaction" {
    var empty: [0]u8 = .{};
    try std.testing.expectEqual(@as(usize, 0), (try strip.stripAnsi("\x1b[0m", &empty)).len);
    try std.testing.expectError(error.NoSpace, strip.stripAnsi("x", &empty));
    var short: [1]u8 = undefined;
    try std.testing.expectError(error.NoSpace, strip.stripAnsi("\x1b[31mé", &short));
    try std.testing.expectEqual(@as(u8, 0xc3), short[0]); // Byte-only partial output.
    var input = "\x1b[31mcafé\x1b[0m".*;
    const result = try strip.stripAnsi(&input, &input);
    try std.testing.expectEqualStrings("café", result);
}
