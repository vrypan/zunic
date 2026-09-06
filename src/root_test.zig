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

test "grapheme clusters retain the shared terminal measure" {
    const text = "e\xcc\x81界👩‍👩‍👧‍👦\x00";
    var it = unicode.grapheme.iterator(text);
    while (it.next()) |span| {
        const measured = unicode.width.measureCluster(text[span.start..span.end]);
        try std.testing.expectEqual(measured.columns, span.columns);
    }
}

test "ASCII arrays agree with the fused record" {
    // The trie is verified exhaustively against the pinned UCD by
    // src/tools/test-properties.py. What that cannot see is scalar.at's ASCII
    // shortcut, which reads two separate arrays and hard-codes one column.
    const properties = @import("properties.zig");
    var cp: u7 = 0;
    while (true) {
        const r = properties.record(cp);
        try std.testing.expectEqual(properties.grapheme_ascii[cp], properties.graphemeOf(r));
        try std.testing.expectEqual(properties.line_break_ascii[cp], r.line_break);
        try std.testing.expectEqual(@as(u2, 1), r.width);
        if (cp == 127) break;
        cp += 1;
    }
}
