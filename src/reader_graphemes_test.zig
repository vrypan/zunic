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
    start: u64,
    end: u64,
    point: ?u21,
    starts_new: bool,
    is_final: bool,
) !void {
    const update = (try it.next()).?;
    try std.testing.expectEqual(start, update.grapheme.start);
    try std.testing.expectEqual(end, update.grapheme.end);
    try std.testing.expectEqual(point, if (update.point) |p| p.value else null);
    try std.testing.expectEqual(starts_new, update.starts_new);
    try std.testing.expectEqual(is_final, update.is_final);
    try std.testing.expectEqual(end, it.offset);
}

test "ASCII uses one update per scalar and one final EOF update" {
    var input: std.Io.Reader = .fixed("abc");
    var it = reader_input.init(&input).graphemes();
    try expectUpdate(&it, 0, 1, 'a', true, false);
    try expectUpdate(&it, 1, 2, 'b', true, false);
    try expectUpdate(&it, 2, 3, 'c', true, false);
    try expectUpdate(&it, 2, 3, null, false, true);
    try std.testing.expect((try it.next()) == null);
}

test "combining update extends the current snapshot" {
    var input: std.Io.Reader = .fixed("e\u{0301}x");
    var it = reader_input.init(&input).graphemes();
    try expectUpdate(&it, 0, 1, 'e', true, false);
    try expectUpdate(&it, 0, 3, 0x0301, false, false);
    try expectUpdate(&it, 3, 4, 'x', true, false);
    try expectUpdate(&it, 3, 4, null, false, true);
    try std.testing.expect((try it.next()) == null);
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
    while (try it.next()) |update| {
        try std.testing.expect(update.grapheme.end >= last_end);
        last_end = update.grapheme.end;
        if (update.point != null) scalar_count += 1;
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
        var it = reader_input.init(&input).graphemes();
        var current_start: usize = 0;
        for (cps[0..cp_len], 0..) |value, i| {
            const update = (try it.next()).?;
            if (breaks[i]) current_start = offsets[i];
            try std.testing.expectEqual(breaks[i], update.starts_new);
            try std.testing.expect(!update.is_final);
            try std.testing.expectEqual(value, update.point.?.value);
            try std.testing.expectEqual(@as(u64, current_start), update.grapheme.start);
            try std.testing.expectEqual(@as(u64, offsets[i + 1]), update.grapheme.end);
        }
        const final = (try it.next()).?;
        try std.testing.expect(final.is_final);
        try std.testing.expect(final.point == null);
        try std.testing.expectEqual(@as(u64, current_start), final.grapheme.start);
        try std.testing.expectEqual(@as(u64, byte_len), final.grapheme.end);
        try std.testing.expect((try it.next()) == null);
    }
}

test "a scalar update never waits for or consumes the following scalar" {
    const samples = [_][]const u8{ "A", "\u{80}", "\u{800}", "\u{10000}" };
    for (samples) |sample| {
        var storage: [4]u8 = undefined;
        var input = Chunked.init(sample, &storage);
        input.fail_at = sample.len;
        var it = reader_input.init(&input.interface).graphemes();
        const update = (try it.next()).?;
        try std.testing.expect(update.point != null);
        try std.testing.expectEqual(@as(u64, sample.len), update.grapheme.end);
        try std.testing.expectError(error.ReadFailed, it.next());
        const reads = input.reads;
        try std.testing.expectError(error.ReadFailed, it.next());
        try std.testing.expectEqual(reads, input.reads);
        try std.testing.expectEqual(@as(u64, sample.len), it.offset);
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
        try expectUpdate(&it, 0, 1, 'a', true, false);
        try std.testing.expectError(case.expected, it.next());
        const reads = input.reads;
        try std.testing.expectError(case.expected, it.next());
        try std.testing.expectEqual(reads, input.reads);
        try std.testing.expectEqual(@as(u64, 1), it.offset);
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
    try std.testing.expectEqual(@as(u64, 0), before_it.offset);

    var middle_storage: [4]u8 = undefined;
    var middle = Chunked.init("\xe2\x82", &middle_storage);
    middle.fail_at = 2;
    var middle_it = reader_input.init(&middle.interface).graphemes();
    try std.testing.expectError(error.ReadFailed, middle_it.next());
    try std.testing.expectEqual(@as(u64, 0), middle_it.offset);

    var rebase_storage: [4]u8 = undefined;
    var rebased = Chunked.init("abc\xe2A", &rebase_storage);
    var rebased_it = reader_input.init(&rebased.interface).graphemes();
    for ("abc") |expected| try std.testing.expectEqual(@as(u21, expected), (try rebased_it.next()).?.point.?.value);
    try std.testing.expectError(error.InvalidUtf8, rebased_it.next());
    try std.testing.expect(rebased.rebases > 0);
    try std.testing.expectEqual(@as(u64, 3), rebased_it.offset);
    const reads = rebased.reads;
    try std.testing.expectError(error.InvalidUtf8, rebased_it.next());
    try std.testing.expectEqual(reads, rebased.reads);
    try std.testing.expectEqual(@as(u8, 0xe2), (try rebased.interface.peek(1))[0]);
}

test "checked u64 offsets are preserved" {
    var input: std.Io.Reader = .fixed("a");
    var it = reader_input.init(&input).graphemes();
    it.points.offset = 0x1_0000_0000;
    try expectUpdate(&it, 0x1_0000_0000, 0x1_0000_0001, 'a', true, false);

    var overflow_input: std.Io.Reader = .fixed("a");
    var overflow = reader_input.init(&overflow_input).graphemes();
    overflow.points.offset = std.math.maxInt(u64);
    try std.testing.expectError(error.OffsetOverflow, overflow.next());
    try std.testing.expectEqual(@as(u64, 0), overflow.offset);
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
    while (try it.next()) |update| {
        if (update.point != null) count += 1;
        if (update.is_final) {
            try std.testing.expectEqual(@as(u64, bytes.len), update.grapheme.end);
            try std.testing.expectEqual(@as(u64, 0), update.grapheme.start);
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
    try expectUpdate(&it, 0, 1, 'e', true, false);
    try expectUpdate(&it, 0, 3, 0x0301, false, false);
    try expectUpdate(&it, 0, 3, null, false, true);
    try std.testing.expect((try it.next()) == null);
}
