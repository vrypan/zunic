const std = @import("std");
const unicode = @import("root.zig");

fn expectLines(bytes: []const u8, options: unicode.wrap.Options, expected: []const []const u8, expected_columns: []const usize) !void {
    var it = try unicode.wrap.iterator(bytes, options);
    for (expected, expected_columns) |want, columns| {
        const line = it.next() orelse return error.TestUnexpectedResult;
        try std.testing.expectEqualStrings(want, bytes[line.start..line.end]);
        try std.testing.expectEqual(columns, line.columns);
    }
    try std.testing.expect(it.next() == null);
}

test "wraps at terminal columns" {
    try expectLines("abc def", .{ .max_columns = 3 }, &.{ "abc", " ", "def" }, &.{ 3, 1, 3 });
    try expectLines("abc def", .{ .max_columns = 3, .overflow = .allow }, &.{ "abc ", "def" }, &.{ 4, 3 });
    try expectLines("界界", .{ .max_columns = 2 }, &.{ "界", "界" }, &.{ 2, 2 });
}

test "wrap preserves graphemes and hard breaks" {
    try expectLines("e\xcc\x81x", .{ .max_columns = 1 }, &.{ "e\xcc\x81", "x" }, &.{ 1, 1 });
    try expectLines("👩‍👩‍👧‍👦x", .{ .max_columns = 2 }, &.{ "👩‍👩‍👧‍👦", "x" }, &.{ 2, 1 });
    try expectLines("a\r\nb\x0cc\xc2\x85d\xe2\x80\xa8e", .{ .max_columns = 80 }, &.{ "a", "b", "c", "d", "e" }, &.{ 1, 1, 1, 1, 1 });
}

test "wrap validates width and empty lines" {
    try std.testing.expectError(error.InvalidWidth, unicode.wrap.iterator("x", .{ .max_columns = 0 }));
    try expectLines("\n", .{ .max_columns = 1 }, &.{""}, &.{0});
    try expectLines("a\n\n", .{ .max_columns = 1 }, &.{ "a", "" }, &.{ 1, 0 });
}
