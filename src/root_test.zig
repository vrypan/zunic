const std = @import("std");
const unicode = @import("root.zig");

test "unicode component compiles as an independent root" {
    const step = unicode.utf8.step("x");
    try std.testing.expectEqual(@as(usize, 1), step.len);
    try std.testing.expectEqual(@as(usize, 2), unicode.text("🇬🇷").width());
}

test "text validation checks the complete byte slice" {
    try unicode.text("").validate();
    try unicode.text("Hello, 世界 👩‍👩‍👧‍👦").validate();
    try unicode.text("\u{fffd}").validate();

    const invalid = [_][]const u8{
        "\xff", // stray byte
        "\xc0\x80", // overlong encoding
        "\xed\xa0\x80", // surrogate
        "\xf4\x90\x80\x80", // above U+10FFFF
        "\xe2\x82", // truncated sequence
        "valid prefix\xe2xvalid suffix", // broken continuation
    };
    for (invalid) |bytes| {
        try std.testing.expectError(error.InvalidUtf8, unicode.text(bytes).validate());
    }
}

test "grapheme traversal retains byte spans and optional terminal measure" {
    const text = "e\xcc\x81界👩‍👩‍👧‍👦\x00";
    var it = unicode.text(text).graphemes().measured().iterator();
    while (it.next()) |span| {
        const measured = @import("width.zig").measureCluster(text[span.start.value..span.end.value]);
        try std.testing.expectEqual(measured.columns, span.columns);
        try std.testing.expectEqual(measured.renderable, span.renderable);
    }
}

test "measured spans carry column and renderability" {
    const text = "\xcc\x81a\u{754c}b";
    try std.testing.expectEqual(@as(usize, 4), unicode.text(text).width());

    // A leading combining mark is its own zero-column cluster; the wide
    // scalar occupies two columns. Callers sum these to locate a column,
    // which is why `columnAt`/`byteAt` are not part of the surface.
    var it = unicode.text(text).graphemes().measured().iterator();
    const first = it.next().?;
    try std.testing.expectEqual(@as(u2, 0), first.columns);
    _ = it.next();
    const wide = it.next().?;
    try std.testing.expectEqual(@as(u2, 2), wide.columns);
    try std.testing.expect(wide.renderable);
}

test "terminators report every hard break as a byte extent" {
    const cases = [_]struct { input: []const u8, spans: []const [2]usize }{
        .{ .input = "a\nb", .spans = &.{.{ 1, 2 }} },
        .{ .input = "a\x0bb", .spans = &.{.{ 1, 2 }} },
        .{ .input = "a\x0cb", .spans = &.{.{ 1, 2 }} },
        .{ .input = "a\rb", .spans = &.{.{ 1, 2 }} },
        // CRLF is one terminator of length two.
        .{ .input = "a\r\nb", .spans = &.{.{ 1, 3 }} },
        .{ .input = "a\u{0085}b", .spans = &.{.{ 1, 3 }} },
        .{ .input = "a\u{2028}b", .spans = &.{.{ 1, 4 }} },
        .{ .input = "a\u{2029}b", .spans = &.{.{ 1, 4 }} },
        // Not terminators: NBSP, and truncated lead bytes.
        .{ .input = "a\u{00a0}b", .spans = &.{} },
        .{ .input = "a\xc2", .spans = &.{} },
        .{ .input = "a\xe2\x80", .spans = &.{} },
        .{ .input = "a\xe2\x80\xa7b", .spans = &.{} },
        // Empty input, and terminators at both edges.
        .{ .input = "", .spans = &.{} },
        .{ .input = "\n", .spans = &.{.{ 0, 1 }} },
        .{ .input = "\n\n", .spans = &.{ .{ 0, 1 }, .{ 1, 2 } } },
        .{ .input = "a\n", .spans = &.{.{ 1, 2 }} },
    };
    for (cases) |case| {
        var it = unicode.text(case.input).terminators().iterator();
        for (case.spans) |want| {
            const got = it.next() orelse return error.TestUnexpectedResult;
            try std.testing.expectEqual(want[0], got.start.value);
            try std.testing.expectEqual(want[1], got.end.value);
        }
        try std.testing.expect(it.next() == null);
        try std.testing.expectEqual(case.spans.len, unicode.text(case.input).terminators().count());
    }
}

test "paragraph content derives from terminators without special cases" {
    // The recipe documented in plans/021: content is the gaps, and the single
    // `pos < len` guard is the terminator-versus-separator decision.
    const cases = [_]struct { input: []const u8, want: []const [2]usize }{
        .{ .input = "", .want = &.{} },
        .{ .input = "a", .want = &.{.{ 0, 1 }} },
        .{ .input = "a\n", .want = &.{.{ 0, 1 }} },
        .{ .input = "\n", .want = &.{.{ 0, 0 }} },
        .{ .input = "a\n\nb", .want = &.{ .{ 0, 1 }, .{ 2, 2 }, .{ 3, 4 } } },
        .{ .input = "a\n\n", .want = &.{ .{ 0, 1 }, .{ 2, 2 } } },
        .{ .input = "a\r\nb", .want = &.{ .{ 0, 1 }, .{ 3, 4 } } },
    };
    for (cases) |case| {
        var found: [8][2]usize = undefined;
        var n: usize = 0;
        var pos: usize = 0;
        var it = unicode.text(case.input).terminators().iterator();
        while (it.next()) |t| {
            found[n] = .{ pos, t.start.value };
            n += 1;
            pos = t.end.value;
        }
        if (pos < case.input.len) {
            found[n] = .{ pos, case.input.len };
            n += 1;
        }
        try std.testing.expectEqual(case.want.len, n);
        for (case.want, found[0..n]) |want, got| try std.testing.expectEqualDeep(want, got);
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

test "word bounds partition the view and name their own types" {
    const line = "The price is $9.99 -unless you pay cash.";

    // The named types are part of the surface: a caller can store the view,
    // the iterator and one item without naming an anonymous type.
    const bounds: unicode.WordBounds = unicode.text(line).wordBounds();
    var it: unicode.WordBoundIterator = bounds.iterator();
    var first: unicode.WordBound = undefined;

    var words: usize = 0;
    var segments: usize = 0;
    var cursor: usize = 0;
    while (it.next()) |segment| : (segments += 1) {
        if (segments == 0) first = segment;
        try std.testing.expectEqual(cursor, segment.start.value);
        cursor = segment.end.value;
        if (segment.is_word) words += 1;
    }
    try std.testing.expectEqual(line.len, cursor);
    try std.testing.expectEqual(@as(usize, 18), segments);
    try std.testing.expectEqual(@as(usize, 8), words);
    try std.testing.expectEqualStrings("The", line[first.start.value..first.end.value]);
    try std.testing.expect(first.is_word);

    // Opening the view scans nothing, and an exhausted iterator stays null.
    try std.testing.expectEqual(@as(?unicode.WordBound, null), it.next());
    var empty = unicode.text("").wordBounds().iterator();
    try std.testing.expectEqual(@as(?unicode.WordBound, null), empty.next());
}

test "the pinned Unicode data version is published" {
    try std.testing.expectEqual(@as(u64, 16), unicode.unicode_version.major);
    try std.testing.expectEqual(@as(u64, 0), unicode.unicode_version.minor);
    try std.testing.expectEqual(@as(u64, 0), unicode.unicode_version.patch);
    // This is the data version, not the package version; the three verifiers
    // under src/tools assert it against the vendored UCD filenames.
    try std.testing.expect(unicode.unicode_version.pre == null);
}

test "Text.normalize is the free function, reached from the view" {
    var buffer: [64]u8 = undefined;
    // Composed input, decomposed output, and the reverse.
    try std.testing.expectEqualSlices(u8, "cafe\u{0301}", try unicode.text("caf\u{00E9}").normalize(.nfd).writeTo(&buffer));
    try std.testing.expectEqualSlices(u8, "caf\u{00E9}", try unicode.text("cafe\u{0301}").normalize(.nfc).writeTo(&buffer));

    // Same iterator type and same scalars as the free function.
    const from_view: unicode.NormalizationIterator(.nfd) = unicode.text("\u{1E69}").normalize(.nfd);
    var view_it = from_view;
    var free_it = unicode.normalize("\u{1E69}", .nfd);
    while (true) {
        const a = try view_it.next();
        const b = try free_it.next();
        try std.testing.expectEqual(b, a);
        if (a == null) break;
    }
}

test "exactly two normalization forms" {
    // NFKC and NFKD are deferred; asking for one must not compile, and the
    // count is asserted so adding a form is a deliberate act.
    try std.testing.expectEqual(@as(usize, 2), @typeInfo(unicode.Form).@"enum".fields.len);
    try std.testing.expectEqual(@as(usize, 1), @typeInfo(unicode.Equivalence).@"enum".fields.len);
}
