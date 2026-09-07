const std = @import("std");
const unicode = @import("root.zig");

fn expectLines(bytes: []const u8, options: unicode.WrapOptions, expected: []const []const u8, expected_columns: []const usize) !void {
    var it = (try unicode.text(bytes).wrap(options)).iterator();
    for (expected, expected_columns) |want, columns| {
        const line = it.next() orelse return error.TestUnexpectedResult;
        try std.testing.expectEqualStrings(want, bytes[line.start.value..line.end.value]);
        try std.testing.expectEqual(columns, line.columns.value);
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
    try std.testing.expectError(error.InvalidWidth, unicode.text("x").wrap(.{ .max_columns = 0 }));
    try expectLines("\n", .{ .max_columns = 1 }, &.{""}, &.{0});
    try expectLines("a\n\n", .{ .max_columns = 1 }, &.{ "a", "" }, &.{ 1, 0 });
}

test "wrap selects fitting candidates and finalizes oversized lines" {
    try expectLines("a bcdef", .{ .max_columns = 4, .overflow = .allow }, &.{ "a ", "bcdef" }, &.{ 2, 5 });
    try expectLines("界\n", .{ .max_columns = 1 }, &.{"界"}, &.{2});
    try expectLines("界\x00", .{ .max_columns = 1 }, &.{"界\x00"}, &.{2});
    try expectLines("界\n\n", .{ .max_columns = 1 }, &.{ "界", "" }, &.{ 2, 0 });
    try expectLines("longword\n", .{ .max_columns = 2, .overflow = .allow }, &.{"longword"}, &.{8});
}

test "wrap retains terminal width for ASCII controls" {
    try expectLines("a\x00b\x7f", .{ .max_columns = 1 }, &.{ "a\x00", "b\x7f" }, &.{ 1, 1 });
}
