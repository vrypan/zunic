const std = @import("std");
const scan = @import("scan.zig");
const grapheme = @import("grapheme.zig");
const line_break = @import("line_break.zig");
const utf8 = @import("utf8.zig");
const scalar = @import("scalar.zig");
const properties = @import("properties.zig");
const width = @import("width.zig");

fn expectScannerMatchesComposedIterators(bytes: []const u8) !void {
    var scanner = scan.Scanner(false){ .bytes = bytes };
    var graphemes = grapheme.iterator(bytes);
    var boundaries = line_break.iterator(bytes);
    var boundary = boundaries.next();
    while (graphemes.next()) |span| {
        while (boundary) |value| {
            if (value.offset >= span.end) break;
            boundary = boundaries.next();
        }
        const cluster = scanner.next() orelse return error.TestUnexpectedResult;
        try std.testing.expectEqual(span.start, cluster.start);
        try std.testing.expectEqual(span.end, cluster.end);
        try std.testing.expectEqual(span.columns, cluster.columns);
        const can_break = boundary != null and boundary.?.offset == span.end and boundary.?.opportunity != .prohibited;
        try std.testing.expectEqual(can_break, cluster.can_break);
        const cp = utf8.step(bytes[span.start..span.end]).cp orelse 0;
        const hard = switch (cp) {
            0x0A, 0x0B, 0x0C, 0x0D, 0x85, 0x2028, 0x2029 => true,
            else => false,
        };
        try std.testing.expectEqual(hard, cluster.hard);
    }
    try std.testing.expect(scanner.next() == null);
    try std.testing.expect(scanner.next() == null);
}

test "fused scanner matches composed grapheme and line-break iterators" {
    const cases = [_][]const u8{
        "",
        "hello, world 123",
        "a bcdef ghi\r\njk\x0cl\xc2\x85m\xe2\x80\xa8n\xe2\x80\xa9o",
        "Καλημέρα cafe\xcc\x81 — λέξεις και τόνοι.",
        "日本語の文章と漢字を測定します。",
        "👩‍👩‍👧‍👦 🇬🇷🇬🇷🇬🇷 👋🏿",
        "valid \xff bytes \xc0\x80 remain bounded \xc2",
        "USD (1.23) and $ (45,678.90) totals",
        "e\xcc\x81\xcc\x81\xcc\x81 \x00\x7f \n\n \r\r\n",
        "क्षि हिन्दी 한국어 조합",
    };
    for (cases) |bytes| try expectScannerMatchesComposedIterators(bytes);
}

test "fused scanner matches composed iterators on randomized atoms" {
    const atoms = [_][]const u8{ "a", " ", "界", "\x00", "\n", "\xff", "e\xcc\x81", "🇬🇷", "👩‍👩‍👧‍👦", "1", ",", ".", "(", ")", "$", "\r\n", "\xc2\x85" };
    var random = std.Random.DefaultPrng.init(0xfaded_5eed);
    var buffer: [256]u8 = undefined;
    for (0..300) |_| {
        var length: usize = 0;
        const count = random.random().intRangeAtMost(usize, 0, 32);
        for (0..count) |_| {
            const atom = atoms[random.random().uintLessThan(usize, atoms.len)];
            if (length + atom.len > buffer.len) break;
            @memcpy(buffer[length..][0..atom.len], atom);
            length += atom.len;
        }
        try expectScannerMatchesComposedIterators(buffer[0..length]);
    }
}

fn countScalars(bytes: []const u8) usize {
    var count: usize = 0;
    var pos: usize = 0;
    while (pos < bytes.len) {
        pos += utf8.step(bytes[pos..]).len;
        count += 1;
    }
    return count;
}

test "fused scanner decodes each scalar once with a bounded buffer" {
    const cases = [_][]const u8{
        "wörter über zwölf tage",
        "日本語の文章と漢字を測定します。",
        "👩‍👩‍👧‍👦 🇬🇷 👋🏿",
        "e\xcc\x81\xcc\x81\xcc\x81\xcc\x81\xcc\x81",
    };
    for (cases) |bytes| {
        var scanner = scan.Scanner(true){ .bytes = bytes };
        while (scanner.next()) |_| {}
        try std.testing.expectEqual(countScalars(bytes), scanner.counters.decoded_scalars);
        try std.testing.expect(scanner.counters.max_buffered <= 2);
    }
}

test "ASCII detectors agree at all byte positions and slice offsets" {
    var storage: [48]u8 = undefined;
    @memset(&storage, 'a');
    for (0..17) |offset| {
        for (0..33) |length| {
            const bytes = storage[offset..][0..length];
            try std.testing.expect(scan.ascii.scalarAllLetters(bytes));
            try std.testing.expect(scan.ascii.simdAllLetters(bytes));
        }
    }
    for (0..33) |position| {
        for (0..256) |value| {
            @memset(&storage, 'a');
            storage[position] = @intCast(value);
            const lower: u8 = @intCast(value | 0x20);
            const expected = lower >= 'a' and lower <= 'z';
            try std.testing.expectEqual(expected, scan.ascii.scalarAllLetters(storage[0..33]));
            try std.testing.expectEqual(expected, scan.ascii.simdAllLetters(storage[0..33]));
        }
    }
}

/// `scalar.at` without the ASCII shortcut, written straight from the general
/// rules, so the shortcut is checked against the path it replaces.
fn referenceAt(bytes: []const u8, start: usize) scalar.Token {
    const step = utf8.step(bytes[start..]);
    const cp = step.cp;
    return .{
        .start = start,
        .end = start + step.len,
        .codepoint = cp,
        .grapheme = if (cp) |v| properties.graphemeProperties(v) else .{ .gcb = .other, .incb = .none, .extended_pictographic = false },
        .line_break = if (cp) |v| properties.lineBreak(v) else .al,
        .cell_width = if (cp) |v| scalar.codepointWidth(v) else 0,
    };
}

fn expectSameToken(bytes: []const u8, start: usize) !void {
    const want = referenceAt(bytes, start);
    const got = scalar.at(bytes, start);
    try std.testing.expectEqual(want.start, got.start);
    try std.testing.expectEqual(want.end, got.end);
    try std.testing.expectEqual(want.codepoint, got.codepoint);
    try std.testing.expectEqual(want.line_break, got.line_break);
    try std.testing.expectEqual(want.cell_width, got.cell_width);
    try std.testing.expectEqual(want.grapheme.gcb, got.grapheme.gcb);
    try std.testing.expectEqual(want.grapheme.incb, got.grapheme.incb);
    try std.testing.expectEqual(want.grapheme.extended_pictographic, got.grapheme.extended_pictographic);
}

test "scalar.at ASCII shortcut matches the general path for every byte" {
    // Every byte value alone, at the end of input, and followed by bytes that
    // would change a multi-byte decode.
    const tails = [_][]const u8{ "", "a", "\x80", "\xcc\x81", "\xff", "\n" };
    for (0..256) |value| {
        var buffer: [8]u8 = undefined;
        buffer[0] = @intCast(value);
        for (tails) |tail| {
            @memcpy(buffer[1..][0..tail.len], tail);
            try expectSameToken(buffer[0 .. 1 + tail.len], 0);
        }
    }
}

test "scalar.at ASCII shortcut matches the general path at every offset" {
    const cases = [_][]const u8{
        "plain ascii text, with punctuation 123.",
        "mixed \xce\xba\xe1\xbd\xb9 ascii and greek",
        "e\xcc\x81 combining, \xf0\x9f\x91\x8b emoji, \xff malformed",
        "\x00\x01\x7f\x20 controls and space",
        "\r\n\x0b\x0c hard separators",
    };
    for (cases) |bytes| {
        for (0..bytes.len + 1) |start| try expectSameToken(bytes, start);
    }
}

test "paragraph classifiers agree at all byte positions and lengths" {
    var storage: [40]u8 = undefined;
    for (0..40) |position| {
        for (0..256) |value| {
            @memset(&storage, 'a');
            storage[position] = @intCast(value);
            for ([_]usize{ 1, 15, 16, 17, 31, 32, 33, 40 }) |length| {
                if (position >= length) continue;
                const bytes = storage[0..length];
                try std.testing.expectEqual(
                    scan.ascii.scalarParagraph(bytes),
                    scan.ascii.simdParagraph(bytes),
                );
            }
        }
    }
}

test "paragraph accepts the documented alphabet and rejects the rest" {
    for (0..256) |value| {
        const byte: u8 = @intCast(value);
        var buffer = [_]u8{ 'a', byte, 'a' };
        const expected_simple = switch (byte) {
            'a'...'z', 'A'...'Z', '0'...'9', ' ', 0x0A...0x0D => true,
            '"', '#', '&', '\'', '*', ',', '.', ':', ';', '=', '@', '_' => true,
            else => false,
        };
        const got = scan.ascii.scalarParagraph(&buffer) != .none;
        try std.testing.expectEqual(expected_simple, got);
    }
}

/// `textWidth` without the printable-ASCII shortcut.
fn referenceTextWidth(bytes: []const u8) usize {
    var it = grapheme.iterator(bytes);
    var total: usize = 0;
    while (it.next()) |span| total += if (span.columns == 3) 1 else span.columns;
    return total;
}

test "textWidth shortcut matches the grapheme iterator for every byte" {
    var storage: [40]u8 = undefined;
    for (0..40) |position| {
        for (0..256) |value| {
            @memset(&storage, 'a');
            storage[position] = @intCast(value);
            for ([_]usize{ 1, 15, 16, 17, 31, 33, 40 }) |length| {
                if (position >= length) continue;
                const bytes = storage[0..length];
                try std.testing.expectEqual(referenceTextWidth(bytes), width.textWidth(bytes));
            }
        }
    }
}

test "textWidth shortcut matches the grapheme iterator on mixed text" {
    const cases = [_][]const u8{
        "",
        " ",
        "plain ascii, punctuation 123.",
        "tab\there and newline\nhere",
        "\x00\x1f\x7f controls",
        "wide \xe6\x97\xa5\xe6\x9c\xac cjk",
        "combining e\xcc\x81 and emoji \xf0\x9f\x91\x8b\xf0\x9f\x8f\xbf",
        "malformed \xff \xc0\x80 bytes",
        "regional \xf0\x9f\x87\xac\xf0\x9f\x87\xb7 indicator",
    };
    for (cases) |bytes| {
        try std.testing.expectEqual(referenceTextWidth(bytes), width.textWidth(bytes));
    }
}

test "printable detectors agree at all byte positions and lengths" {
    var storage: [48]u8 = undefined;
    for (0..40) |position| {
        for (0..256) |value| {
            @memset(&storage, 'a');
            storage[position] = @intCast(value);
            for ([_]usize{ 1, 15, 16, 17, 31, 32, 33, 40 }) |length| {
                if (position >= length) continue;
                const bytes = storage[0..length];
                try std.testing.expectEqual(
                    scan.ascii.scalarAllPrintable(bytes),
                    scan.ascii.simdAllPrintable(bytes),
                );
            }
        }
    }
}
