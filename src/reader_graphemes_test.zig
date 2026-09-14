const std = @import("std");
const reader_input = @import("reader_input");

const fixture = @embedFile("data/GraphemeBreakTest-17.0.0.txt");

const Chunked = struct {
    data: []const u8,
    cursor: usize = 0,
    max_chunk: usize = 1,
    reads: usize = 0,
    rebases: usize = 0,
    fail_at: ?usize = null,
    interface: std.Io.Reader,

    fn init(data: []const u8, buffer: []u8) Chunked {
        return .{
            .data = data,
            .interface = .{
                .vtable = &.{ .stream = stream, .rebase = rebase },
                .buffer = buffer,
                .seek = 0,
                .end = 0,
            },
        };
    }

    fn stream(interface: *std.Io.Reader, writer: *std.Io.Writer, limit: std.Io.Limit) std.Io.Reader.StreamError!usize {
        const self: *Chunked = @alignCast(@fieldParentPtr("interface", interface));
        self.reads += 1;
        if (self.fail_at) |at| if (self.cursor >= at) return error.ReadFailed;
        if (self.cursor == self.data.len) return error.EndOfStream;
        const limited = limit.toInt() orelse std.math.maxInt(usize);
        const n = @min(self.max_chunk, limited, self.data.len - self.cursor);
        const written = try writer.write(self.data[self.cursor..][0..n]);
        self.cursor += written;
        return written;
    }

    fn rebase(interface: *std.Io.Reader, capacity: usize) std.Io.Reader.RebaseError!void {
        const self: *Chunked = @alignCast(@fieldParentPtr("interface", interface));
        self.rebases += 1;
        return std.Io.Reader.defaultRebase(interface, capacity);
    }
};

fn expectUpdate(
    it: *reader_input.ReaderGraphemeIterator,
    end: u64,
    point: ?u21,
    starts_new: bool,
    is_final: bool,
) !void {
    const update = (try it.next()).?;
    var encoded: [4]u8 = undefined;
    const len = if (point) |value| try std.unicode.utf8Encode(value, &encoded) else 0;
    try std.testing.expectEqualSlices(u8, encoded[0..len], update.bytes());
    try std.testing.expectEqual(starts_new, update.starts_new);
    try std.testing.expectEqual(is_final, update.is_final);
    try std.testing.expectEqual(end, it.points.offset);
}

test "ASCII uses one update per scalar and one final EOF update" {
    var input: std.Io.Reader = .fixed("abc");
    var it = reader_input.init(&input).graphemes();
    try expectUpdate(&it, 1, 'a', true, false);
    try expectUpdate(&it, 2, 'b', true, false);
    try expectUpdate(&it, 3, 'c', true, false);
    try expectUpdate(&it, 3, null, false, true);
    try std.testing.expect((try it.next()) == null);
}

test "combining update extends the current snapshot" {
    var input: std.Io.Reader = .fixed("e\u{0301}x");
    var it = reader_input.init(&input).graphemes();
    try expectUpdate(&it, 1, 'e', true, false);
    try expectUpdate(&it, 3, 0x0301, false, false);
    try expectUpdate(&it, 4, 'x', true, false);
    try expectUpdate(&it, 4, null, false, true);
    try std.testing.expect((try it.next()) == null);
}

test "updates own their bytes across copies and Reader buffer reuse" {
    const pieces = [_][]const u8{ "\x00", "\u{80}", "\u{800}", "\u{10000}", "\u{10ffff}", "z" };
    const bytes = "\x00\u{80}\u{800}\u{10000}\u{10ffff}z";
    var storage: [4]u8 = undefined;
    var input = Chunked.init(bytes, &storage);
    var it = reader_input.init(&input.interface).graphemes();
    var retained: [pieces.len]reader_input.ReaderGraphemeUpdate = undefined;
    for (&retained) |*update| update.* = (try it.next()).?;
    const final = (try it.next()).?;
    try std.testing.expect(final.is_final);
    try std.testing.expectEqual(@as(usize, 0), final.bytes().len);
    try std.testing.expect((try it.next()) == null);
    try std.testing.expect(input.rebases > 0);
    @memset(&storage, 0xff);
    const copied = retained;
    for (&retained, &copied, pieces) |*saved, *copy, expected| {
        try std.testing.expectEqualSlices(u8, expected, saved.bytes());
        try std.testing.expectEqualSlices(u8, expected, copy.bytes());
    }
}

test "grapheme updates preserve every valid UTF-8 scalar encoding" {
    var encoded: [4]u8 = undefined;
    for (0..0x110000) |value| {
        if (value >= 0xd800 and value <= 0xdfff) continue;
        const len = try std.unicode.utf8Encode(@intCast(value), &encoded);
        var input: std.Io.Reader = .fixed(encoded[0..len]);
        var it = reader_input.init(&input).graphemes();
        const update = (try it.next()).?;
        try std.testing.expectEqualSlices(u8, encoded[0..len], update.bytes());
        try std.testing.expect(update.starts_new);
        try std.testing.expect(!update.is_final);
        const final = (try it.next()).?;
        try std.testing.expect(final.is_final);
        try std.testing.expectEqual(@as(usize, 0), final.bytes().len);
        try std.testing.expect((try it.next()) == null);
    }
}

test "empty supported input has no update" {
    var storage: [1]u8 = undefined;
    var input = Chunked.init("", &storage);
    var it = reader_input.init(&input.interface).graphemes();
    try std.testing.expectEqual(@as(usize, 0), input.reads);
    try std.testing.expect((try it.next()) == null);
    try std.testing.expectEqual(@as(usize, 1), input.reads);
    try std.testing.expect((try it.next()) == null);
    try std.testing.expectEqual(@as(usize, 1), input.reads);
}

test "contextual grapheme rules survive one-byte refills and rebases" {
    const bytes = "\r\n" ++
        "a\u{0301}" ++
        "\u{0600}b" ++
        "\u{1100}\u{1161}\u{11a8}" ++
        "\u{1f600}\u{200d}\u{1f600}" ++
        "\u{0915}\u{094d}\u{0915}" ++
        "\u{1f1e6}\u{1f1e7}\u{1f1e8}";
    var storage: [4]u8 = undefined;
    var input = Chunked.init(bytes, &storage);
    var it = reader_input.init(&input.interface).graphemes();
    var scalar_count: usize = 0;
    var last_end: u64 = 0;
    const boundaries = [_]bool{
        true, false, // CR LF
        true, false, // base + Extend
        true, false, // Prepend + base
        true, false, false, // Hangul
        true, false, false, // pictographic ZWJ sequence
        true, false, false, // Indic conjunct
        true, false, true, // regional indicator pair + single
    };
    while (try it.next()) |update| {
        if (update.bytes().len != 0) {
            try std.testing.expect(scalar_count < boundaries.len);
            try std.testing.expectEqual(boundaries[scalar_count], update.starts_new);
            try std.testing.expect(!update.is_final);
            scalar_count += 1;
        } else {
            try std.testing.expect(update.is_final);
            try std.testing.expect(!update.starts_new);
        }
        last_end += update.bytes().len;
    }
    try std.testing.expectEqual(@as(usize, 18), scalar_count);
    try std.testing.expectEqual(@as(u64, bytes.len), last_end);
    try std.testing.expect(input.rebases > 0);
}

test "updates match every Unicode 17 grapheme fixture" {
    var lines = std.mem.splitScalar(u8, fixture, '\n');
    while (lines.next()) |raw_line| {
        const line = raw_line[0 .. std.mem.indexOfScalar(u8, raw_line, '#') orelse raw_line.len];
        if (std.mem.trim(u8, line, " \t\r").len == 0) continue;

        var cps: [64]u21 = undefined;
        var breaks: [65]bool = undefined;
        var cp_len: usize = 0;
        var break_len: usize = 0;
        var tokens = std.mem.tokenizeAny(u8, line, " \t\r");
        while (tokens.next()) |token| {
            if (std.mem.eql(u8, token, "÷") or std.mem.eql(u8, token, "×")) {
                breaks[break_len] = std.mem.eql(u8, token, "÷");
                break_len += 1;
            } else {
                cps[cp_len] = try std.fmt.parseInt(u21, token, 16);
                cp_len += 1;
            }
        }
        try std.testing.expectEqual(cp_len + 1, break_len);

        var bytes: [256]u8 = undefined;
        var offsets: [65]usize = undefined;
        var byte_len: usize = 0;
        for (cps[0..cp_len], 0..) |value, i| {
            offsets[i] = byte_len;
            byte_len += try std.unicode.utf8Encode(value, bytes[byte_len..]);
        }
        offsets[cp_len] = byte_len;

        var input: std.Io.Reader = .fixed(bytes[0..byte_len]);
        try expectFixture(&input, cps[0..cp_len], breaks[0..break_len], offsets[0 .. cp_len + 1]);
        var storage: [8]u8 = undefined;
        for (4..9) |capacity| {
            for (1..5) |chunk_size| {
                var chunked = Chunked.init(bytes[0..byte_len], storage[0..capacity]);
                chunked.max_chunk = chunk_size;
                try expectFixture(&chunked.interface, cps[0..cp_len], breaks[0..break_len], offsets[0 .. cp_len + 1]);
                if (byte_len > capacity) try std.testing.expect(chunked.rebases > 0);
            }
        }
    }
}

fn expectFixture(input: *std.Io.Reader, cps: []const u21, breaks: []const bool, offsets: []const usize) !void {
    var it = reader_input.init(input).graphemes();
    var consumed: usize = 0;
    for (cps, 0..) |value, i| {
        const update = (try it.next()).?;
        try std.testing.expectEqual(breaks[i], update.starts_new);
        try std.testing.expect(!update.is_final);
        var encoded: [4]u8 = undefined;
        const len = try std.unicode.utf8Encode(value, &encoded);
        try std.testing.expectEqualSlices(u8, encoded[0..len], update.bytes());
        consumed += update.bytes().len;
        try std.testing.expectEqual(offsets[i + 1], consumed);
    }
    const final = (try it.next()).?;
    try std.testing.expect(final.is_final);
    try std.testing.expect(!final.starts_new);
    try std.testing.expectEqual(@as(usize, 0), final.bytes().len);
    try std.testing.expectEqual(offsets[cps.len], consumed);
    try std.testing.expect((try it.next()) == null);
    try std.testing.expect((try it.next()) == null);
}

test "a scalar update never waits for or consumes the following scalar" {
    const samples = [_][]const u8{ "A", "\u{80}", "\u{800}", "\u{10000}" };
    for (samples) |sample| {
        var storage: [4]u8 = undefined;
        var input = Chunked.init(sample, &storage);
        input.fail_at = sample.len;
        var it = reader_input.init(&input.interface).graphemes();
        const update = (try it.next()).?;
        try std.testing.expectEqualSlices(u8, sample, update.bytes());
        try std.testing.expectEqual(@as(u64, sample.len), it.points.offset);
        try std.testing.expectError(error.ReadFailed, it.next());
        const reads = input.reads;
        try std.testing.expectError(error.ReadFailed, it.next());
        try std.testing.expectEqual(reads, input.reads);
        try std.testing.expectEqual(@as(u64, sample.len), it.points.offset);
    }
}

test "decoder failures do not finalize or advance grapheme state" {
    const cases = [_]struct { bytes: []const u8, expected: reader_input.ReaderGraphemeError }{
        .{ .bytes = "a\xff", .expected = error.InvalidUtf8 },
        .{ .bytes = "a\xe0\x80", .expected = error.InvalidUtf8 },
        .{ .bytes = "a\xed\xa0", .expected = error.InvalidUtf8 },
        .{ .bytes = "a\xf4\x90", .expected = error.InvalidUtf8 },
        .{ .bytes = "a\xe2\x82", .expected = error.InvalidUtf8 },
    };
    for (cases) |case| {
        var storage: [4]u8 = undefined;
        var input = Chunked.init(case.bytes, &storage);
        var it = reader_input.init(&input.interface).graphemes();
        try expectUpdate(&it, 1, 'a', true, false);
        try std.testing.expectError(case.expected, it.next());
        const reads = input.reads;
        try std.testing.expectError(case.expected, it.next());
        try std.testing.expectEqual(reads, input.reads);
        try std.testing.expectEqual(@as(u64, 1), it.points.offset);
        try std.testing.expectEqual(case.bytes[1], (try input.interface.peek(1))[0]);
    }

    var zero: std.Io.Reader = .fixed("");
    var zero_it = reader_input.init(&zero).graphemes();
    try std.testing.expectError(error.ReaderBufferTooSmall, zero_it.next());

    var cap2: [2]u8 = undefined;
    var short = Chunked.init("\xe2\x82", &cap2);
    var short_it = reader_input.init(&short.interface).graphemes();
    try std.testing.expectError(error.ReaderBufferTooSmall, short_it.next());
}

test "read failures and rebased malformed bytes stay provisional" {
    var before_storage: [4]u8 = undefined;
    var before = Chunked.init("a", &before_storage);
    before.fail_at = 0;
    var before_it = reader_input.init(&before.interface).graphemes();
    try std.testing.expectError(error.ReadFailed, before_it.next());
    try std.testing.expectEqual(@as(u64, 0), before_it.points.offset);

    var middle_storage: [4]u8 = undefined;
    var middle = Chunked.init("\xe2\x82", &middle_storage);
    middle.fail_at = 2;
    var middle_it = reader_input.init(&middle.interface).graphemes();
    try std.testing.expectError(error.ReadFailed, middle_it.next());
    try std.testing.expectEqual(@as(u64, 0), middle_it.points.offset);

    var rebase_storage: [4]u8 = undefined;
    var rebased = Chunked.init("abc\xe2A", &rebase_storage);
    var rebased_it = reader_input.init(&rebased.interface).graphemes();
    for ("abc") |expected| {
        const update = (try rebased_it.next()).?;
        try std.testing.expectEqualSlices(u8, &.{expected}, update.bytes());
    }
    try std.testing.expectError(error.InvalidUtf8, rebased_it.next());
    try std.testing.expect(rebased.rebases > 0);
    try std.testing.expectEqual(@as(u64, 3), rebased_it.points.offset);
    const reads = rebased.reads;
    try std.testing.expectError(error.InvalidUtf8, rebased_it.next());
    try std.testing.expectEqual(reads, rebased.reads);
    try std.testing.expectEqual(@as(u8, 0xe2), (try rebased.interface.peek(1))[0]);
}

test "checked u64 offsets are preserved" {
    var input: std.Io.Reader = .fixed("a");
    var it = reader_input.init(&input).graphemes();
    it.points.offset = 0x1_0000_0000;
    try expectUpdate(&it, 0x1_0000_0001, 'a', true, false);

    var overflow_input: std.Io.Reader = .fixed("a");
    var overflow = reader_input.init(&overflow_input).graphemes();
    overflow.points.offset = std.math.maxInt(u64);
    try std.testing.expectError(error.OffsetOverflow, overflow.next());
    try std.testing.expectEqual(std.math.maxInt(u64), overflow.points.offset);
    try std.testing.expectEqual(@as(u8, 'a'), (try overflow_input.peek(1))[0]);
}

test "long grapheme uses bounded iterator state" {
    const mark_count = 100_000;
    const bytes = try std.testing.allocator.alloc(u8, 1 + mark_count * 2);
    defer std.testing.allocator.free(bytes);
    bytes[0] = 'a';
    for (0..mark_count) |i| {
        bytes[1 + i * 2] = 0xcc;
        bytes[2 + i * 2] = 0x81;
    }

    var storage: [4]u8 = undefined;
    var input = Chunked.init(bytes, &storage);
    var it = reader_input.init(&input.interface).graphemes();
    var count: usize = 0;
    var byte_count: usize = 0;
    while (try it.next()) |update| {
        if (update.bytes().len != 0) {
            try std.testing.expectEqual(count == 0, update.starts_new);
            byte_count += update.bytes().len;
            count += 1;
        }
        if (update.is_final) {
            try std.testing.expect(!update.starts_new);
            try std.testing.expectEqual(bytes.len, byte_count);
        }
    }
    try std.testing.expectEqual(mark_count + 1, count);
    try std.testing.expect(@sizeOf(reader_input.ReaderGraphemeIterator) <= 64);
}

test "file Reader and a pre-consumed source use a fresh offset origin" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const file = try tmp.dir.createFile(io, "reader-graphemes.txt", .{ .read = true });
    defer file.close(io);

    var write_buffer: [16]u8 = undefined;
    var writer: std.Io.File.Writer = .init(file, io, &write_buffer);
    try writer.interface.writeAll("xe\u{0301}");
    try writer.interface.flush();

    var read_buffer: [4]u8 = undefined;
    var file_reader = file.readerStreaming(io, &read_buffer);
    try std.testing.expectEqual(@as(u8, 'x'), try file_reader.interface.takeByte());
    const source = reader_input.init(&file_reader.interface);
    var it = source.graphemes();
    try expectUpdate(&it, 1, 'e', true, false);
    try expectUpdate(&it, 3, 0x0301, false, false);
    try expectUpdate(&it, 3, null, false, true);
    try std.testing.expect((try it.next()) == null);
}
