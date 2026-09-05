const std = @import("std");
const unicode = @import("root.zig");

test "unicode component compiles as an independent root" {
    const step = unicode.utf8.step("x");
    try std.testing.expectEqual(@as(usize, 1), step.len);
    try std.testing.expectEqual(@as(u3, 2), unicode.width.measureCluster("🇬🇷").columns);
}

test "scalar iterator retains byte spans and facts" {
    var it = unicode.scalar.iterator("a\xff界");
    const a = it.next().?;
    try std.testing.expectEqual(@as(usize, 0), a.start);
    try std.testing.expectEqual(@as(?u21, 'a'), a.codepoint);
    const invalid = it.next().?;
    try std.testing.expect(invalid.codepoint == null);
    try std.testing.expectEqual(@as(usize, 2), invalid.end);
    const cjk = it.next().?;
    try std.testing.expectEqual(@as(?u21, 0x754C), cjk.codepoint);
    try std.testing.expect(it.next() == null);
}
