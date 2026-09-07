const std = @import("std");
const unicode = @import("zunic");
const reference = @import("wrap_reference.zig");

fn expectProductionMatchesReference(bytes: []const u8, options: unicode.WrapOptions) !void {
    const expected = try reference.collect(std.testing.allocator, bytes, options);
    defer std.testing.allocator.free(expected);

    var actual = (try unicode.text(bytes).wrap(options)).iterator();
    for (expected) |want| {
        const got = actual.next() orelse return error.TestUnexpectedResult;
        try std.testing.expectEqual(want.start, got.start.value);
        try std.testing.expectEqual(want.end, got.end.value);
        try std.testing.expectEqual(want.columns, got.columns.value);
    }
    try std.testing.expect(actual.next() == null);
    try std.testing.expect(actual.next() == null);
}

test "wrap matches independent reference regressions" {
    const Case = struct { bytes: []const u8, width: usize, overflow: unicode.Overflow };
    const cases = [_]Case{
        .{ .bytes = "a bcdef", .width = 4, .overflow = .allow },
        .{ .bytes = "abc def", .width = 3, .overflow = .grapheme },
        .{ .bytes = "abc def", .width = 3, .overflow = .allow },
        .{ .bytes = "界\n", .width = 1, .overflow = .grapheme },
        .{ .bytes = "界\x00", .width = 1, .overflow = .grapheme },
        .{ .bytes = "界\n\n", .width = 1, .overflow = .grapheme },
        .{ .bytes = "longword\n", .width = 2, .overflow = .allow },
        .{ .bytes = "a\x0bb\x0cc\xc2\x85d\xe2\x80\xa8e\xe2\x80\xa9", .width = 1, .overflow = .grapheme },
        .{ .bytes = "\xff\xc0\x80 e\xcc\x81 🇬🇷👩‍👩‍👧‍👦", .width = 2, .overflow = .grapheme },
        .{ .bytes = "123,456.78 9", .width = 3, .overflow = .allow },
        .{ .bytes = "", .width = 1, .overflow = .grapheme },
    };
    for (cases) |case| try expectProductionMatchesReference(case.bytes, .{ .max_columns = case.width, .overflow = case.overflow });
}

test "wrap matches independent reference randomized" {
    const atoms = [_][]const u8{ "a", " ", "界", "\x00", "\n", "\xff", "e\xcc\x81", "🇬🇷", "👩‍👩‍👧‍👦", "1", ",", "\r\n" };
    var random = std.Random.DefaultPrng.init(0x5eed_600d);
    var buffer: [256]u8 = undefined;
    const widths = [_]usize{ 1, 2, 3, 4, 40, 80 };
    for (0..200) |_| {
        var length: usize = 0;
        const count = random.random().intRangeAtMost(usize, 0, 24);
        for (0..count) |_| {
            const atom = atoms[random.random().uintLessThan(usize, atoms.len)];
            if (length + atom.len > buffer.len) break;
            @memcpy(buffer[length..][0..atom.len], atom);
            length += atom.len;
        }
        const bytes = buffer[0..length];
        for (widths) |max_columns| {
            try expectProductionMatchesReference(bytes, .{ .max_columns = max_columns, .overflow = .grapheme });
            try expectProductionMatchesReference(bytes, .{ .max_columns = max_columns, .overflow = .allow });
        }
    }
}

test "ASCII fast path preserves word and viewport lines" {
    try expectProductionMatchesReference("abcdefghijklmnopqrstuvwxyz", .{ .max_columns = 5, .overflow = .grapheme });
    try expectProductionMatchesReference("abcdefghijklmnopqrstuvwxyz", .{ .max_columns = 5, .overflow = .allow });
    try expectProductionMatchesReference("abc\xcc\x81def", .{ .max_columns = 3, .overflow = .grapheme });
    try expectProductionMatchesReference("abc def", .{ .max_columns = 3, .overflow = .allow });
    try expectProductionMatchesReference("alpha beta gamma\r\ndelta", .{ .max_columns = 6, .overflow = .grapheme });
    try expectProductionMatchesReference("alpha beta gamma\r\ndelta", .{ .max_columns = 6, .overflow = .allow });
}

fn countScalars(bytes: []const u8) usize {
    var count: usize = 0;
    var pos: usize = 0;
    while (pos < bytes.len) {
        pos += unicode.utf8.step(bytes[pos..]).len;
        count += 1;
    }
    return count;
}

// The 008 work bound: the wrapper decodes each scalar exactly once (the
// scanner never rewinds and LB25's rare extra lookahead is absent from these
// corpora), with at most two tokens buffered, at every width, in both
// overflow policies, at every input scale. Replay would show up here as a
// superlinear decode count.
test "wrapping decodes each scalar once at all scales and widths" {
    const seeds = [_][]const u8{
        "wörter über zwölf lange tage hinweg ",
        "ööööööööööööööööööööööööööööööö",
        "e\xcc\x81\xcc\x81\xcc\x81\xcc\x81\xcc\x81\xcc\x81\xcc\x81\xcc\x81",
        "日本語の文章と漢字を測定します。 ",
    };
    var buffer: [4096]u8 = undefined;
    for (seeds) |seed| {
        for ([_]usize{ 1, 2, 4, 8 }) |scale| {
            var length: usize = 0;
            for (0..scale) |_| {
                @memcpy(buffer[length..][0..seed.len], seed);
                length += seed.len;
            }
            const bytes = buffer[0..length];
            const expected = countScalars(bytes);
            for ([_]usize{ 1, 3, 40 }) |max_columns| {
                for ([_]unicode.Overflow{ .grapheme, .allow }) |overflow| {
                    var it = try unicode.testing.instrumentedIterator(bytes, .{ .max_columns = max_columns, .overflow = overflow });
                    while (it.next()) |_| {}
                    try std.testing.expectEqual(expected, it.scanner.counters.decoded_scalars);
                    try std.testing.expect(it.scanner.counters.max_buffered <= 2);
                }
            }
        }
    }
}

test "viewport wrapping stays lazy" {
    var buffer: [4096]u8 = undefined;
    const seed = "wörter über zwölf lange tage hinweg ";
    var length: usize = 0;
    while (length + seed.len <= buffer.len) : (length += seed.len) {
        @memcpy(buffer[length..][0..seed.len], seed);
    }
    const bytes = buffer[0..length];
    var it = try unicode.testing.instrumentedIterator(bytes, .{ .max_columns = 20, .overflow = .grapheme });
    for (0..4) |_| _ = it.next() orelse return error.TestUnexpectedResult;
    try std.testing.expect(it.scanner.counters.decoded_scalars < countScalars(bytes) / 2);
}

test "ASCII paragraph fast path matches reference exhaustively" {
    // 0x0B and 0x0C are both line-break class BK and grapheme class Control,
    // so one of them represents the pair; LF and CR are separate classes and
    // stay. `.` stands for the infix separators and, with `7` present, covers
    // the digit exception. `zig build wrap-exhaustive` sweeps the full set.
    const alphabet = [_]u8{ 'a', 'Z', '7', '.', ' ', '\n', '\r', 0x0B };
    var buffer: [5]u8 = undefined;
    for (0..6) |length| {
        const combinations = std.math.pow(usize, alphabet.len, length);
        for (0..combinations) |value| {
            var remaining = value;
            for (0..length) |index| {
                buffer[index] = alphabet[remaining % alphabet.len];
                remaining /= alphabet.len;
            }
            for ([_]usize{ 1, 2, 3 }) |max_columns| {
                try expectProductionMatchesReference(buffer[0..length], .{ .max_columns = max_columns, .overflow = .grapheme });
                try expectProductionMatchesReference(buffer[0..length], .{ .max_columns = max_columns, .overflow = .allow });
            }
        }
    }
}
