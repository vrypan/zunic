const std = @import("std");
const scan = @import("scan.zig");
const grapheme = @import("grapheme.zig");
const line_break = @import("line_break.zig");
const utf8 = @import("utf8.zig");

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
