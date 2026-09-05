const std = @import("std");
const scan = @import("scan.zig");

test "ASCII detectors agree at all byte positions and slice offsets" {
    var storage: [48]u8 = undefined;
    @memset(&storage, 'a');
    for (0..17) |offset| {
        for (0..33) |length| {
            const bytes = storage[offset..][0..length];
            try std.testing.expect(scan.ascii.scalarAllLetters(bytes));
            try std.testing.expect(scan.ascii.simdAllLetters(bytes));
        }
    }
    for (0..33) |position| {
        for (0..256) |value| {
            @memset(&storage, 'a');
            storage[position] = @intCast(value);
            const lower: u8 = @intCast(value | 0x20);
            const expected = lower >= 'a' and lower <= 'z';
            try std.testing.expectEqual(expected, scan.ascii.scalarAllLetters(storage[0..33]));
            try std.testing.expectEqual(expected, scan.ascii.simdAllLetters(storage[0..33]));
        }
    }
}
