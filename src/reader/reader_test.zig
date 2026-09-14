const std = @import("std");
const reader_input = @import("reader_input");
const cp = @import("cp");

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

fn expectSticky(it: *reader_input.ReaderCodepointIterator, expected: reader_input.ReaderCodepointError) !void {
    try std.testing.expectError(expected, it.next());
    const offset = it.offset;
    try std.testing.expectError(expected, it.next());
    try std.testing.expectEqual(offset, it.offset);
}

test "fixed Reader yields views and stable EOF" {
    const bytes = "A\u{80}\u{800}\u{10000}\u{fffd}\u{10ffff}";
    var input: std.Io.Reader = .fixed(bytes);
    const source = reader_input.init(&input);
    var it = source.codepoints();
    const expected = [_]u21{ 'A', 0x80, 0x800, 0x10000, 0xfffd, 0x10ffff };
    var offset: u64 = 0;
    for (expected) |value| {
        const point = (try it.next()).?;
        try std.testing.expectEqualDeep(cp.init(value), point);
        offset += std.unicode.utf8CodepointSequenceLength(value) catch unreachable;
        try std.testing.expectEqual(offset, it.offset);
    }
    try std.testing.expect((try it.next()) == null);
    try std.testing.expect((try it.next()) == null);
}

test "construction is lazy and clean EOF is stable" {
    var storage: [1]u8 = undefined;
    var input = Chunked.init("", &storage);
    const source = reader_input.init(&input.interface);
    var it = source.codepoints();
    try std.testing.expectEqual(@as(usize, 0), input.reads);
    try std.testing.expect((try it.next()) == null);
    try std.testing.expectEqual(@as(usize, 1), input.reads);
    try std.testing.expect((try it.next()) == null);
    try std.testing.expectEqual(@as(usize, 1), input.reads);
}

test "every Unicode scalar roundtrips" {
    var encoded: [4]u8 = undefined;
    for (0..0x110000) |value| {
        if (value >= 0xd800 and value <= 0xdfff) continue;
        const scalar: u21 = @intCast(value);
        const len = try std.unicode.utf8Encode(scalar, &encoded);
        var input: std.Io.Reader = .fixed(encoded[0..len]);
        var it = reader_input.init(&input).codepoints();
        try std.testing.expectEqual(scalar, (try it.next()).?.value);
        try std.testing.expectEqual(@as(u64, @intCast(len)), it.offset);
        try std.testing.expect((try it.next()) == null);
    }
}

test "short refills work at every split and do not require a later scalar" {
    const samples = [_][]const u8{ "\u{80}x", "\u{800}x", "\u{ffff}x", "\u{10000}x", "\u{10ffff}x" };
    for (samples) |bytes| {
        var storage: [4]u8 = undefined;
        var input = Chunked.init(bytes, &storage);
        input.max_chunk = 1;
        var it = reader_input.init(&input.interface).codepoints();
        const expected = try std.unicode.utf8Decode(bytes[0..try std.unicode.utf8ByteSequenceLength(bytes[0])]);
        try std.testing.expectEqual(expected, (try it.next()).?.value);
    }

    var storage: [1]u8 = undefined;
    var input = Chunked.init("A", &storage);
    input.fail_at = 1;
    var it = reader_input.init(&input.interface).codepoints();
    try std.testing.expectEqual(@as(u21, 'A'), (try it.next()).?.value);
    try std.testing.expectEqual(@as(usize, 1), input.reads);
}

test "invalid prefixes fail early, stay unconsumed, and latch" {
    const cases = [_]struct { bytes: []const u8, reads: usize }{
        .{ .bytes = "\xff", .reads = 1 },
        .{ .bytes = "\xe2A", .reads = 2 },
        .{ .bytes = "\xe0\x80", .reads = 2 },
        .{ .bytes = "\xed\xa0", .reads = 2 },
        .{ .bytes = "\xf0\x80", .reads = 2 },
        .{ .bytes = "\xf4\x90", .reads = 2 },
        .{ .bytes = "\xe2\x82A", .reads = 3 },
        .{ .bytes = "\xf0\x9f\x91A", .reads = 4 },
    };
    for (cases) |case| {
        var storage: [4]u8 = undefined;
        var input = Chunked.init(case.bytes, &storage);
        var it = reader_input.init(&input.interface).codepoints();
        try expectSticky(&it, error.InvalidUtf8);
        try std.testing.expectEqual(@as(u64, 0), it.offset);
        try std.testing.expectEqual(case.reads, input.reads);
        try std.testing.expectEqual(case.bytes[0], (try input.interface.peek(1))[0]);
    }
}

test "malformed prefix remains logically available after forced rebase" {
    var storage: [4]u8 = undefined;
    var input = Chunked.init("abc\xe2A", &storage);
    var it = reader_input.init(&input.interface).codepoints();

    for ("abc") |expected| try std.testing.expectEqual(@as(u21, expected), (try it.next()).?.value);
    try std.testing.expectEqual(@as(u64, 3), it.offset);
    try std.testing.expectEqual(@as(usize, 0), input.rebases);

    try std.testing.expectError(error.InvalidUtf8, it.next());
    try std.testing.expectEqual(@as(usize, 1), input.rebases);
    try std.testing.expectEqual(@as(u64, 3), it.offset);
    const reads = input.reads;

    try std.testing.expectError(error.InvalidUtf8, it.next());
    try std.testing.expectEqual(reads, input.reads);
    try std.testing.expectEqual(@as(u64, 3), it.offset);
    try std.testing.expectEqual(@as(u8, 0xe2), (try input.interface.peek(1))[0]);
    try std.testing.expectEqual(reads, input.reads);
}

test "capacity and truncation precedence" {
    var zero: std.Io.Reader = .fixed("");
    var it = reader_input.init(&zero).codepoints();
    try expectSticky(&it, error.ReaderBufferTooSmall);

    var failing = std.Io.Reader.failing;
    it = reader_input.init(&failing).codepoints();
    try expectSticky(&it, error.ReaderBufferTooSmall);

    var ascii: std.Io.Reader = .fixed("A");
    it = reader_input.init(&ascii).codepoints();
    try std.testing.expectEqual(@as(u21, 'A'), (try it.next()).?.value);

    var cap2: [2]u8 = undefined;
    var malformed = Chunked.init("\xe2A", &cap2);
    it = reader_input.init(&malformed.interface).codepoints();
    try expectSticky(&it, error.InvalidUtf8);

    var incomplete = Chunked.init("\xe2\x82", &cap2);
    it = reader_input.init(&incomplete.interface).codepoints();
    try expectSticky(&it, error.ReaderBufferTooSmall);

    var cap4: [4]u8 = undefined;
    var truncated = Chunked.init("\xe2\x82", &cap4);
    it = reader_input.init(&truncated.interface).codepoints();
    try expectSticky(&it, error.InvalidUtf8);

    const four = "\u{1f600}";
    var backing: [4]u8 = undefined;
    for (0..5) |capacity| {
        var sized = Chunked.init(four, backing[0..capacity]);
        it = reader_input.init(&sized.interface).codepoints();
        if (capacity < 4)
            try expectSticky(&it, error.ReaderBufferTooSmall)
        else
            try std.testing.expectEqual(@as(u21, 0x1f600), (try it.next()).?.value);
    }
}

test "every incomplete scalar prefix is invalid with adequate capacity" {
    const samples = [_][]const u8{ "\u{80}", "\u{800}", "\u{10000}" };
    for (samples) |sample| {
        for (1..sample.len) |length| {
            var storage: [4]u8 = undefined;
            var input = Chunked.init(sample[0..length], &storage);
            var it = reader_input.init(&input.interface).codepoints();
            try expectSticky(&it, error.InvalidUtf8);
            try std.testing.expectEqual(@as(u64, 0), it.offset);
        }
    }
}

test "read failures are distinct and sticky at each position" {
    const cases = [_]struct { bytes: []const u8, fail_at: usize, expected_offset: u64 }{
        .{ .bytes = "A", .fail_at = 0, .expected_offset = 0 },
        .{ .bytes = "\xe2\x82", .fail_at = 2, .expected_offset = 0 },
        .{ .bytes = "A", .fail_at = 1, .expected_offset = 1 },
    };
    for (cases) |case| {
        var storage: [4]u8 = undefined;
        var input = Chunked.init(case.bytes, &storage);
        input.fail_at = case.fail_at;
        var it = reader_input.init(&input.interface).codepoints();
        if (case.expected_offset == 1) _ = (try it.next()).?;
        try expectSticky(&it, error.ReadFailed);
        try std.testing.expectEqual(case.expected_offset, it.offset);
    }
}

test "offset overflow precedes consumption" {
    var input: std.Io.Reader = .fixed("ab");
    var it = reader_input.init(&input).codepoints();
    it.offset = std.math.maxInt(u64);
    try expectSticky(&it, error.OffsetOverflow);
    try std.testing.expectEqual(@as(u8, 'a'), (try input.peek(1))[0]);
}

test "concrete streaming File reader" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const file = try tmp.dir.createFile(io, "reader.txt", .{ .read = true });
    defer file.close(io);
    var write_buffer: [16]u8 = undefined;
    var writer: std.Io.File.Writer = .init(file, io, &write_buffer);
    try writer.interface.writeAll("A\u{20ac}\u{1f600}");
    try writer.interface.flush();
    var read_buffer: [4]u8 = undefined;
    var file_reader = file.readerStreaming(io, &read_buffer);
    var it = reader_input.init(&file_reader.interface).codepoints();
    for ([_]u21{ 'A', 0x20ac, 0x1f600 }) |expected|
        try std.testing.expectEqual(expected, (try it.next()).?.value);
    try std.testing.expect((try it.next()) == null);
}
