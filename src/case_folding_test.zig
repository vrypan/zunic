const std = @import("std");
const codepoints = @import("cp");
const fixture = @embedFile("data/CaseFolding-17.0.0.txt");

fn expectFold(cp: u21, expected: []const u21) !void {
    const result = codepoints.init(cp).fullCaseFold();
    try std.testing.expectEqualSlices(u21, expected, result.slice());
    for (result.codepoints[result.len..]) |unused| try std.testing.expectEqual(@as(u21, 0), unused);
}

test "full default case folding" {
    try expectFold('A', &.{'a'});
    try expectFold(0x00df, &.{ 's', 's' });
    try expectFold(0x0130, &.{ 0x0069, 0x0307 });
    try expectFold(0x03a3, &.{0x03c3});
    try expectFold(0x03c2, &.{0x03c3});
    try expectFold(0x0390, &.{ 0x03b9, 0x0308, 0x0301 });
    try expectFold(0x1f600, &.{0x1f600});
    try expectFold(0x110000, &.{0x110000});
}

test "case fold result owns its bounded storage" {
    var result = codepoints.init(0x00df).fullCaseFold();
    const borrowed = result.slice();
    try std.testing.expectEqualSlices(u21, &.{ 's', 's' }, borrowed);
}

test "bounded fold results compare scalar keys without allocation" {
    var kelvin = codepoints.init(0x212a).fullCaseFold();
    var ascii_k = codepoints.init('K').fullCaseFold();
    try std.testing.expect(std.mem.eql(u21, kelvin.slice(), ascii_k.slice()));

    var final_sigma = codepoints.init(0x03c2).fullCaseFold();
    var capital_sigma = codepoints.init(0x03a3).fullCaseFold();
    try std.testing.expect(std.mem.eql(u21, final_sigma.slice(), capital_sigma.slice()));
}

test "every C and F mapping and every identity agree with CaseFolding.txt" {
    const seen = try std.testing.allocator.alloc(bool, 0x110000);
    defer std.testing.allocator.free(seen);
    @memset(seen, false);

    var lines = std.mem.splitScalar(u8, fixture, '\n');
    while (lines.next()) |raw| {
        const content = raw[0 .. std.mem.indexOfScalar(u8, raw, '#') orelse raw.len];
        const line = std.mem.trim(u8, content, " \t\r");
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, ';');
        const cp_text = std.mem.trim(u8, fields.next() orelse return error.TestUnexpectedResult, " \t");
        const status = std.mem.trim(u8, fields.next() orelse return error.TestUnexpectedResult, " \t");
        const mapping_text = std.mem.trim(u8, fields.next() orelse return error.TestUnexpectedResult, " \t");
        if (!std.mem.eql(u8, status, "C") and !std.mem.eql(u8, status, "F")) continue;
        const cp = try std.fmt.parseInt(u21, cp_text, 16);
        var expected: [3]u21 = .{ 0, 0, 0 };
        var expected_len: usize = 0;
        var values = std.mem.tokenizeScalar(u8, mapping_text, ' ');
        while (values.next()) |value| {
            if (expected_len == expected.len) return error.TestUnexpectedResult;
            expected[expected_len] = try std.fmt.parseInt(u21, value, 16);
            expected_len += 1;
        }
        try expectFold(cp, expected[0..expected_len]);
        seen[cp] = true;
    }

    for (seen, 0..) |mapped, raw| {
        if (mapped) continue;
        const cp: u21 = @intCast(raw);
        try expectFold(cp, &.{cp});
    }
}
