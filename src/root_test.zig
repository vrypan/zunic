const std = @import("std");
const unicode = @import("root.zig");

test "unicode component compiles as an independent root" {
    const step = unicode.utf8.step("x");
    try std.testing.expectEqual(@as(usize, 1), step.len);
    try std.testing.expectEqual(@as(usize, 2), unicode.width("🇬🇷"));
}

test "grapheme lens retains byte spans and optional terminal measure" {
    const text = "e\xcc\x81界👩‍👩‍👧‍👦\x00";
    var it = unicode.graphemes(text).measured().iterator();
    while (it.next()) |span| {
        const measured = @import("width.zig").measureCluster(text[span.start.value..span.end.value]);
        try std.testing.expectEqual(measured.columns, span.columns);
        try std.testing.expectEqual(measured.renderable, span.renderable);
    }
}

test "lens coordinates preserve grapheme and column ambiguity" {
    const text = "\xcc\x81a界b";
    try std.testing.expectEqual(@as(usize, 4), unicode.width(text));

    // Leading zero-width clusters share column zero; `byteAt` selects the
    // earliest one.  The second cell of 界 is deliberately a straddle.
    const zero = unicode.byteAt(text, .init(0));
    try std.testing.expectEqual(@as(usize, 0), zero.cluster.start.value);
    try std.testing.expectEqual(@as(usize, 0), zero.column.value);
    const wide = unicode.byteAt(text, .init(2));
    try std.testing.expectEqual(@as(usize, 3), wide.cluster.start.value);
    try std.testing.expectEqual(@as(usize, 1), wide.column.value);
    try std.testing.expect(wide.column.value != 2); // requested column straddles

    // A byte within a cluster maps to that cluster's first column.
    try std.testing.expectEqual(@as(usize, 1), unicode.columnAt(text, .init(4)).value);
    const past = unicode.byteAt(text, .init(99));
    try std.testing.expectEqual(text.len, past.cluster.start.value);
    try std.testing.expectEqual(@as(usize, 4), past.column.value);
}

test "ColumnHit carries no policy field" {
    comptime {
        if (@hasField(unicode.ColumnHit, "straddled") or @hasField(unicode.ColumnHit, "straddles"))
            @compileError("ColumnHit derives straddling from requested != column; do not store it");
    }
}

test "grapheme indexing is caller-owned" {
    var spans: [3]unicode.Span = undefined;
    const indexed = unicode.graphemes("a界b").indexed(&spans);
    try std.testing.expectEqual(@as(usize, 3), indexed.count());
    try std.testing.expectEqual(@as(usize, 1), indexed.at(.init(1)).?.start.value);
}

test "lines is wrapping without a finite column limit" {
    const text = "a\n界\r\nb";
    var lines = unicode.lines(text).iterator();
    var wrapped = (try unicode.wrap(text, .{ .max_columns = std.math.maxInt(usize) })).iterator();
    while (true) {
        const left = lines.next();
        const right = wrapped.next();
        try std.testing.expectEqual(left != null, right != null);
        if (left) |line| {
            const other = right.?;
            try std.testing.expectEqual(line.start.value, other.start.value);
            try std.testing.expectEqual(line.end.value, other.end.value);
            try std.testing.expectEqual(line.columns.value, other.columns.value);
        } else break;
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
