const std = @import("std");
const text_module = @import("text");
const CodepointView = @import("cp").CodepointView;

test "text validation checks the complete byte slice" {
    try text_module.init("").validate();
    try text_module.init("Hello, 世界 👩‍👩‍👧‍👦").validate();
    try text_module.init("\u{fffd}").validate();

    const invalid = [_][]const u8{
        "\xff", // stray byte
        "\xc0\x80", // overlong encoding
        "\xed\xa0\x80", // surrogate
        "\xf4\x90\x80\x80", // above U+10FFFF
        "\xe2\x82", // truncated sequence
        "valid prefix\xe2xvalid suffix", // broken continuation
    };
    for (invalid) |bytes| {
        try std.testing.expectError(error.InvalidUtf8, text_module.init(bytes).validate());
    }
}

test "grapheme traversal retains byte spans and optional terminal measure" {
    const text = "e\xcc\x81界👩‍👩‍👧‍👦\x00";
    var it = text_module.init(text).graphemes().measured().iterator();
    while (it.next()) |span| {
        const measured = @import("layout").width.measureCluster(text[span.start.value..span.end.value]);
        try std.testing.expectEqual(measured.columns, span.columns);
        try std.testing.expectEqual(measured.renderable, span.renderable);
    }
}

test "GB11 permits Extend before one ZWJ but not repeated ZWJs" {
    const emoji = "\u{1F600}";
    for ([_][]const u8{ emoji ++ "\u{200D}\u{200D}", emoji ++ "\u{200D}\u{0301}\u{200D}" }) |prefix| {
        var buffer: [32]u8 = undefined;
        @memcpy(buffer[0..prefix.len], prefix);
        @memcpy(buffer[prefix.len..][0..emoji.len], emoji);
        const bytes = buffer[0 .. prefix.len + emoji.len];
        var it = text_module.init(bytes).graphemes().measured().iterator();
        for ([_][2]usize{ .{ 0, prefix.len }, .{ prefix.len, bytes.len } }) |expected| {
            const span = it.next() orelse return error.TestUnexpectedResult;
            try std.testing.expectEqual(expected[0], span.start.value);
            try std.testing.expectEqual(expected[1], span.end.value);
            try std.testing.expectEqual(@as(u2, 2), span.columns);
        }
        try std.testing.expect(it.next() == null);
        try std.testing.expectEqual(@as(usize, 4), text_module.init(bytes).width());
        var lines = (try text_module.init(bytes).wrap(.{ .max_columns = 2 })).iterator();
        try std.testing.expectEqual(prefix.len, lines.next().?.end.value);
        try std.testing.expectEqual(bytes.len, lines.next().?.end.value);
        try std.testing.expect(lines.next() == null);
    }
    // Legitimate Extend* ZWJ sequences must remain a single cluster.
    const valid = emoji ++ "\u{0301}\u{200D}" ++ emoji;
    var it = text_module.init(valid).graphemes().iterator();
    try std.testing.expectEqual(valid.len, it.next().?.end.value);
    try std.testing.expect(it.next() == null);
    try std.testing.expectEqual(@as(usize, 2), text_module.init(valid).width());
}

test "measured spans carry column and renderability" {
    const text = "\xcc\x81a\u{754c}b";
    try std.testing.expectEqual(@as(usize, 4), text_module.init(text).width());

    // A leading combining mark is its own zero-column cluster; the wide
    // scalar occupies two columns. Callers sum these to locate a column,
    // which is why `columnAt`/`byteAt` are not part of the surface.
    var it = text_module.init(text).graphemes().measured().iterator();
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
        var it = text_module.init(case.input).terminators().iterator();
        for (case.spans) |want| {
            const got = it.next() orelse return error.TestUnexpectedResult;
            try std.testing.expectEqual(want[0], got.start.value);
            try std.testing.expectEqual(want[1], got.end.value);
        }
        try std.testing.expect(it.next() == null);
        try std.testing.expectEqual(case.spans.len, text_module.init(case.input).terminators().count());
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
        var it = text_module.init(case.input).terminators().iterator();
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

test "codepoints stop at malformed UTF-8 and retain error and byte offset" {
    const invalids = [_][]const u8{
        "\xffvalid", "\x80valid", "\xc0\x80valid", // illegal lead, stray continuation, overlong
        "\xc2", "\xe2\x82", "\xf0\x9f\x98", // truncation
        "\xc2A", "\xe2\x82A", "\xf0\x9f\x98A", // broken continuation
        "\xed\xa0\x80", "\xf4\x90\x80\x80", // surrogate, above Unicode range
        "\xe0\x80\x80", "\xf0\x80\x80\x80", // overlong 3/4-byte forms
    };
    for (invalids) |invalid| {
        var buffer: [32]u8 = undefined;
        const prefix = "a\u{754c}";
        @memcpy(buffer[0..prefix.len], prefix);
        @memcpy(buffer[prefix.len..][0..invalid.len], invalid);
        // Test both an error at the start and an error following valid scalars.
        for ([_][]const u8{ invalid, buffer[0 .. prefix.len + invalid.len] }, [_]usize{ 0, prefix.len }) |bytes, failure_offset| {
            var it = text_module.init(bytes).codepoints().iterator();
            var count: usize = 0;
            while (it.next()) |_| count += 1;
            try std.testing.expectEqual(@as(usize, if (failure_offset == 0) 0 else 2), count);
            try std.testing.expectEqual(failure_offset, it.offset);
            try std.testing.expectEqual(text_module.DecodeError.invalid_utf8, it.err.?);
            try std.testing.expectEqual(@as(?CodepointView, null), it.next());
            try std.testing.expectEqual(@as(?CodepointView, null), it.next());
            try std.testing.expectEqual(failure_offset, it.offset);
            try std.testing.expectEqual(text_module.DecodeError.invalid_utf8, it.err.?);
        }
    }
}

test "empty and copied codepoint iterators retain independent state" {
    var empty = text_module.init("").codepoints().iterator();
    try std.testing.expectEqual(@as(?CodepointView, null), empty.next());
    try std.testing.expectEqual(@as(?CodepointView, null), empty.next());
    try std.testing.expectEqual(@as(?text_module.DecodeError, null), empty.err);
    try std.testing.expectEqual(@as(usize, 0), empty.offset);

    var it = text_module.init("a\xff").codepoints().iterator();
    try std.testing.expectEqual(@as(u21, 'a'), it.next().?.value);
    var checkpoint = it;
    try std.testing.expectEqual(@as(?CodepointView, null), it.next());
    try std.testing.expectEqual(@as(?text_module.DecodeError, null), checkpoint.err);
    try std.testing.expectEqual(@as(usize, 1), checkpoint.offset);
    try std.testing.expectEqual(@as(?CodepointView, null), checkpoint.next());
    try std.testing.expectEqual(text_module.DecodeError.invalid_utf8, checkpoint.err.?);
}
