const std = @import("std");
const unicode = @import("zunic");
const grapheme = @import("segmentation").grapheme;
const scan = @import("layout").scan;
const width = @import("layout").width;
const terminal = @import("tables").terminal_properties;

fn expectWidth(bytes: []const u8, expected: usize) !void {
    try std.testing.expectEqual(expected, unicode.text(bytes).width());
    var spans = unicode.text(bytes).graphemes().measured().iterator();
    var plain = unicode.text(bytes).graphemes().iterator();
    var scanner: scan.Scanner(true) = .{ .bytes = bytes };
    var columns: usize = 0;
    while (spans.next()) |span| {
        const unmeasured = plain.next().?;
        try std.testing.expectEqual(span.start, unmeasured.start);
        try std.testing.expectEqual(span.end, unmeasured.end);
        const cluster = bytes[span.start.value..span.end.value];
        const standalone = width.measureCluster(cluster);
        try std.testing.expectEqual(span.columns, standalone.columns);
        try std.testing.expectEqual(span.renderable, standalone.renderable);
        const scanned = scanner.next().?;
        try std.testing.expectEqual(span.start.value, scanned.start);
        try std.testing.expectEqual(span.end.value, scanned.end);
        try std.testing.expectEqual(@as(usize, span.columns), grapheme.displayColumns(scanned.columns));
        columns += span.columns;

        // Every Reader prefix must match a slice of the same open cluster.
        if (std.unicode.utf8ValidateSlice(cluster)) {
            var input: std.Io.Reader = .fixed(cluster);
            var reader = unicode.reader(&input).graphemes().measured();
            var end: usize = 0;
            while (try reader.next()) |update| {
                end += update.bytes().len;
                const prefix = width.measureCluster(cluster[0..end]);
                try std.testing.expectEqual(prefix.columns, update.columns);
                try std.testing.expectEqual(prefix.renderable, update.renderable);
            }
        }
    }
    try std.testing.expect(plain.next() == null);
    try std.testing.expect(scanner.next() == null);
    try std.testing.expectEqual(expected, columns);
    var lines = (try unicode.text(bytes).wrap(.{ .max_columns = 80 })).iterator();
    var wrapped_columns: usize = 0;
    while (lines.next()) |line| {
        try std.testing.expectEqual(unicode.text(bytes[line.start.value..line.end.value]).width(), line.columns.value);
        wrapped_columns += line.columns.value;
    }
    try std.testing.expectEqual(expected, wrapped_columns);
}

test "presentation selectors and default widths agree across measurement APIs" {
    const cases = [_]struct { bytes: []const u8, columns: usize }{
        .{ .bytes = "▪", .columns = 1 },
        .{ .bytes = "©", .columns = 1 },
        .{ .bytes = "❤", .columns = 1 },
        .{ .bytes = "▪\u{fe0e}", .columns = 1 },
        .{ .bytes = "▪\u{fe0f}", .columns = 2 },
        .{ .bytes = "©\u{fe0f}", .columns = 2 },
        .{ .bytes = "⌚", .columns = 2 },
        .{ .bytes = "⌚\u{fe0e}", .columns = 1 },
        .{ .bytes = "⌚\u{fe0f}", .columns = 2 },
        .{ .bytes = "\u{1f21a}\u{fe0e}", .columns = 2 },
        .{ .bytes = "〰\u{fe0e}", .columns = 2 },
        .{ .bytes = "⌚\u{fe0e}\u{fe0f}", .columns = 1 },
        .{ .bytes = "⌚\u{fe0f}\u{fe0e}", .columns = 2 },
        .{ .bytes = "▪\u{fe0e}\u{fe0f}", .columns = 1 },
        .{ .bytes = "▪\u{301}\u{fe0f}", .columns = 1 },
        .{ .bytes = "⌚\u{301}\u{fe0e}", .columns = 2 },
        .{ .bytes = "a\u{fe0f}", .columns = 1 },
        .{ .bytes = "\u{fe0f}", .columns = 0 },
        .{ .bytes = "\u{301}\u{fe0f}", .columns = 0 },
        .{ .bytes = "#\u{fe0f}", .columns = 2 },
        .{ .bytes = "*\u{fe0f}\u{20e3}", .columns = 2 },
        .{ .bytes = "1\u{fe0f}\u{20e3}", .columns = 2 },
        .{ .bytes = "1\u{20e3}", .columns = 1 },
        .{ .bytes = "#\u{fe0e}\u{20e3}", .columns = 1 },
        .{ .bytes = "#\u{301}\u{fe0f}\u{20e3}", .columns = 1 },
        .{ .bytes = "😀\u{fe0e}", .columns = 2 },
        .{ .bytes = "👩‍👩‍👧‍👦", .columns = 2 },
        .{ .bytes = "❤\u{fe0f}\u{200d}🔥", .columns = 2 },
        .{ .bytes = "👋🏿", .columns = 2 },
        .{ .bytes = "⛹\u{fe0e}🏿", .columns = 2 },
        .{ .bytes = "🇬", .columns = 2 },
        .{ .bytes = "🇬🇷", .columns = 2 },
        .{ .bytes = "\u{1fc00}", .columns = 1 },
        .{ .bytes = "▪\xff\u{fe0f}", .columns = 1 },
        .{ .bytes = "abcdefghijklmnop#\u{fe0f}\u{20e3}x", .columns = 19 },
        .{ .bytes = "▪⌚\u{fe0e}▪\u{fe0f}", .columns = 4 },
    };
    for (cases) |case| try expectWidth(case.bytes, case.columns);
}

test "all pinned emoji variation bases and selectors" {
    var lines = std.mem.splitScalar(u8, @embedFile("data/emoji-variation-sequences-17.0.0.txt"), '\n');
    var tested: usize = 0;
    while (lines.next()) |line| {
        if (line.len == 0 or line[0] == '#') continue;
        const space = std.mem.indexOfScalar(u8, line, ' ') orelse continue;
        const base = try std.fmt.parseInt(u21, line[0..space], 16);
        // The fixture lists each base twice. Exercise bare, VS15 and VS16 once.
        if (!std.mem.startsWith(u8, line[space + 1 ..], "FE0E")) continue;
        var bytes: [8]u8 = undefined;
        const len = try std.unicode.utf8Encode(base, &bytes);
        const properties = terminal.terminalProperties(base);
        const bare = unicode.cp(base).width();
        try expectWidth(bytes[0..len], bare);
        const text_width = if (properties.emoji_presentation and !(base >= 0x1f200 and base <= 0x1f2ff)) 1 else bare;
        const text_len = try std.unicode.utf8Encode(0xfe0e, bytes[len..]);
        try expectWidth(bytes[0 .. len + text_len], text_width);
        const emoji_len = try std.unicode.utf8Encode(0xfe0f, bytes[len..]);
        try expectWidth(bytes[0 .. len + emoji_len], 2);
        tested += 3;
    }
    try std.testing.expectEqual(@as(usize, 1113), tested);
}

test "all pinned pictographs keep their scalar default width" {
    var lines = std.mem.splitScalar(u8, @embedFile("data/emoji-data-17.0.0.txt"), '\n');
    var tested: usize = 0;
    while (lines.next()) |line| {
        if (line.len == 0 or line[0] == '#') continue;
        const semicolon = std.mem.indexOfScalar(u8, line, ';') orelse continue;
        if (!std.mem.startsWith(u8, std.mem.trimStart(u8, line[semicolon + 1 ..], " "), "Extended_Pictographic")) continue;
        const range = std.mem.trim(u8, line[0..semicolon], " ");
        const dots = std.mem.indexOf(u8, range, "..");
        const first = try std.fmt.parseInt(u21, range[0 .. dots orelse range.len], 16);
        const last = if (dots) |offset| try std.fmt.parseInt(u21, range[offset + 2 ..], 16) else first;
        for (first..@as(usize, last) + 1) |value| {
            var bytes: [4]u8 = undefined;
            const cp: u21 = @intCast(value);
            const len = try std.unicode.utf8Encode(cp, &bytes);
            try expectWidth(bytes[0..len], unicode.cp(cp).width());
            tested += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 2848), tested);
}

test "exceptional rescans are once per cluster and ordinary text is not rescanned" {
    const ordinary = "Привет 世界 नमस्ते 한국어 ❤ © 👩‍👩‍👧‍👦";
    var plain: scan.Scanner(true) = .{ .bytes = ordinary };
    while (plain.next()) |_| {}
    try std.testing.expectEqual(@as(usize, 0), plain.counters.presentation.decoded_scalars);

    // An arbitrarily long exceptional cluster is still one second pass.
    const exceptional = "❤" ++ "\u{301}" ** 10_000 ++ "\u{fe0f}";
    var scanner: scan.Scanner(true) = .{ .bytes = exceptional };
    try std.testing.expectEqual(@as(u3, 1), scanner.next().?.columns);
    try std.testing.expect(scanner.next() == null);
    try std.testing.expectEqual(@as(usize, 10_002), scanner.counters.decoded_scalars);
    try std.testing.expectEqual(@as(usize, 10_002), scanner.counters.presentation.decoded_scalars);
    try std.testing.expectEqual(@as(usize, 10_003), scanner.counters.presentation.property_lookups);
    try std.testing.expect(scanner.counters.max_buffered <= 2);
}

test "wrapping fits corrected narrow and wide presentations" {
    const bytes = "▪▪▪\u{fe0f}⌚\u{fe0e}";
    var lines = (try unicode.text(bytes).wrap(.{ .max_columns = 2, .overflow = .grapheme })).iterator();
    for ([_][]const u8{ "▪▪", "▪\u{fe0f}", "⌚\u{fe0e}" }) |expected| {
        const line = lines.next().?;
        try std.testing.expectEqualStrings(expected, bytes[line.start.value..line.end.value]);
        try std.testing.expectEqual(unicode.text(expected).width(), line.columns.value);
    }
    try std.testing.expect(lines.next() == null);
}

test "wrapping never replays presentation clusters when moving a saved break" {
    const bytes = "▪▪\u{fe0f} words ⌚\u{fe0e} #\u{fe0f}\u{20e3} 👩‍👩‍👧‍👦 " ** 32;
    const scalars = std.unicode.utf8CountCodepoints(bytes) catch unreachable;
    for ([_]usize{ 1, 2, 3, 8, 40 }) |columns| {
        for ([_]unicode.Overflow{ .allow, .grapheme }) |overflow| {
            var it = try unicode.testing.instrumentedIterator(bytes, .{ .max_columns = columns, .overflow = overflow });
            while (it.next()) |line| {
                try std.testing.expectEqual(unicode.text(bytes[line.start..line.end]).width(), line.columns);
            }
            const counters = it.scanner.counters;
            try std.testing.expect(counters.presentation.decoded_scalars > 0);
            try std.testing.expect(counters.presentation.decoded_scalars <= scalars);
            try std.testing.expect(counters.decoded_scalars + counters.presentation.decoded_scalars < 3 * scalars);
        }
    }
}
