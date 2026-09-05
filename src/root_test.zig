const std = @import("std");
const unicode = @import("root.zig");

test "unicode component compiles as an independent root" {
    const step = unicode.utf8.step("x");
    try std.testing.expectEqual(@as(usize, 1), step.len);
    try std.testing.expectEqual(@as(u3, 2), unicode.width.measureCluster("🇬🇷").columns);
}
