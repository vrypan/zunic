//! Run with `zig build benchmark-reader -Doptimize=ReleaseFast`.
//! Counts and span checksums are checked against slice iteration before timing.
const std = @import("std");
const zunic = @import("zunic");
const Work = enum { codepoints, spans, bytes, raw_bytes, measured, remeasured };

// Compile the same consumer against either API for before/after measurements.
fn updateBytes(update: anytype, scratch: *[4]u8) ![]const u8 {
    if (@hasDecl(@TypeOf(update.*), "bytes")) return update.bytes();
    if (update.point) |point| {
        const len = try std.unicode.utf8Encode(point.value, scratch);
        return scratch[0..len];
    }
    return &.{};
}

fn byteChecksum(bytes: []const u8) u64 {
    var sum: u64 = 0;
    for (bytes, 1..) |byte, i| sum +%= @as(u64, byte) *% i;
    return sum;
}

const Chunked = struct {
    data: []const u8,
    cursor: usize = 0,
    interface: std.Io.Reader,

    fn init(data: []const u8, buffer: []u8) Chunked {
        return .{ .data = data, .interface = .{ .vtable = &.{ .stream = stream }, .buffer = buffer, .seek = 0, .end = 0 } };
    }

    fn stream(interface: *std.Io.Reader, writer: *std.Io.Writer, limit: std.Io.Limit) std.Io.Reader.StreamError!usize {
        const self: *Chunked = @alignCast(@fieldParentPtr("interface", interface));
        if (self.cursor == self.data.len) return error.EndOfStream;
        const n = @min(@as(usize, 1), limit.toInt() orelse 1);
        const written = try writer.write(self.data[self.cursor..][0..n]);
        self.cursor += written;
        return written;
    }
};

const Result = struct {
    scalars: u64 = 0,
    boundaries: u64 = 0,
    finals: u64 = 0,
    checksum: u64 = 0,

    fn point(self: *Result, value: u21, end: u64) void {
        self.scalars += 1;
        self.checksum +%= @as(u64, value) *% (end +% 1);
    }

    fn span(self: *Result, start: u64, end: u64, boundary: bool, final: bool) void {
        self.boundaries += @intFromBool(boundary);
        self.finals += @intFromBool(final);
        self.checksum +%= start *% 17 +% end *% 31 +% @as(u64, @intFromBool(boundary)) *% 43 +% @as(u64, @intFromBool(final)) *% 59;
    }
};

fn scan(comptime work: Work, input: *std.Io.Reader) !Result {
    const with_measure = work == .measured or work == .remeasured;
    const native_measure = work == .measured and @hasDecl(zunic.ReaderGraphemeIterator, "measured");
    var result: Result = .{};
    if (work != .codepoints) {
        // Bounded only for these benchmark corpora, not a library limit.
        var accumulated: [4096]u8 = undefined;
        var length: usize = 0;
        var offset: u64 = 0;
        var cluster_start: u64 = 0;
        var it = if (native_measure) zunic.reader(input).graphemes().measured() else zunic.reader(input).graphemes();
        while (try it.next()) |update| {
            if (!update.is_final) result.scalars += 1;
            if (work == .raw_bytes or with_measure) {
                result.span(0, 0, update.starts_new, update.is_final);
            } else if (@hasField(zunic.ReaderGraphemeUpdate, "grapheme")) {
                result.span(update.grapheme.start, update.grapheme.end, update.starts_new, update.is_final);
            } else {
                // A consumer needing positions can track them from byte lengths.
                if (update.starts_new) cluster_start = offset;
                offset += update.bytes().len;
                result.span(cluster_start, offset, update.starts_new, update.is_final);
            }
            if (work == .bytes or work == .raw_bytes or with_measure) {
                if (update.starts_new) {
                    result.checksum +%= byteChecksum(accumulated[0..length]);
                    length = 0;
                }
                var scratch: [4]u8 = undefined;
                const bytes = try updateBytes(&update, &scratch);
                if (length + bytes.len > accumulated.len) return error.BenchmarkClusterTooLong;
                @memcpy(accumulated[length..][0..bytes.len], bytes);
                length += bytes.len;
                if (update.is_final) result.checksum +%= byteChecksum(accumulated[0..length]);
                if (native_measure) {
                    result.checksum +%= measurementChecksum(update.columns, update.renderable);
                } else if (with_measure) {
                    result.checksum +%= prefixMeasurement(accumulated[0..length]);
                }
            }
        }
    } else {
        var it = zunic.reader(input).codepoints();
        while (try it.next()) |point| result.point(point.value, it.offset);
    }
    return result;
}

fn run(comptime work: Work, comptime chunked: bool, bytes: []const u8, iterations: usize) !Result {
    var total: Result = .{};
    for (0..iterations) |_| {
        std.mem.doNotOptimizeAway(bytes);
        var storage: [4]u8 = undefined;
        var short = Chunked.init(bytes, &storage);
        var fixed: std.Io.Reader = .fixed(bytes);
        const result = try scan(work, if (chunked) &short.interface else &fixed);
        total.scalars +%= result.scalars;
        total.boundaries +%= result.boundaries;
        total.finals +%= result.finals;
        total.checksum +%= result.checksum;
    }
    return total;
}

fn expected(comptime work: Work, bytes: []const u8) !Result {
    const with_measure = work == .measured or work == .remeasured;
    var result: Result = .{};
    var clusters = zunic.text(bytes).graphemes().iterator();
    var last_start: usize = 0;
    while (clusters.next()) |cluster| {
        last_start = cluster.start.value;
        var offset = last_start;
        while (offset < cluster.end.value) {
            const length = try std.unicode.utf8ByteSequenceLength(bytes[offset]);
            const value = try std.unicode.utf8Decode(bytes[offset..][0..length]);
            const boundary = offset == last_start;
            offset += length;
            if (work == .codepoints) result.point(value, offset) else result.scalars += 1;
            if (work == .raw_bytes or with_measure) result.span(0, 0, boundary, false) else if (work != .codepoints) result.span(last_start, offset, boundary, false);
            if (with_measure) result.checksum +%= prefixMeasurement(bytes[last_start..offset]);
        }
        if (work == .bytes or work == .raw_bytes or with_measure) result.checksum +%= byteChecksum(bytes[last_start..cluster.end.value]);
    }
    if (bytes.len != 0) {
        if (work == .raw_bytes or with_measure) result.span(0, 0, false, true) else if (work != .codepoints) result.span(last_start, bytes.len, false, true);
        if (with_measure) result.checksum +%= prefixMeasurement(bytes[last_start..]);
    }
    return result;
}

fn measurementChecksum(columns: u2, renderable: bool) u64 {
    return @as(u64, columns) * 67 + @as(u64, @intFromBool(renderable)) * 71;
}

fn prefixMeasurement(bytes: []const u8) u64 {
    var it = zunic.text(bytes).graphemes().measured().iterator();
    const measured = it.next().?;
    return measurementChecksum(measured.columns, measured.renderable);
}

fn verifyBytes(bytes: []const u8, comptime chunked: bool) !void {
    var storage: [4]u8 = undefined;
    var short = Chunked.init(bytes, &storage);
    var fixed: std.Io.Reader = .fixed(bytes);
    var it = zunic.reader(if (chunked) &short.interface else &fixed).graphemes();
    var offset: usize = 0;
    while (try it.next()) |update| {
        var scratch: [4]u8 = undefined;
        const got = try updateBytes(&update, &scratch);
        if (update.is_final) {
            if (got.len != 0 or offset != bytes.len) return error.BenchmarkMismatch;
        } else {
            const len = try std.unicode.utf8ByteSequenceLength(bytes[offset]);
            if (!std.mem.eql(u8, got, bytes[offset..][0..len])) return error.BenchmarkMismatch;
            offset += len;
        }
    }
    if (offset != bytes.len) return error.BenchmarkMismatch;
}

fn measure(io: std.Io, out: *std.Io.Writer, name: []const u8, bytes: []const u8) !void {
    try verifyBytes(bytes, false);
    try verifyBytes(bytes, true);
    inline for (.{ Work.codepoints, Work.spans, Work.bytes, Work.raw_bytes, Work.measured, Work.remeasured }) |work| {
        const oracle = try expected(work, bytes);
        inline for (.{ false, true }) |chunked| {
            if (!std.meta.eql(oracle, try run(work, chunked, bytes, 1))) return error.BenchmarkMismatch;
            std.mem.doNotOptimizeAway(try run(work, chunked, bytes, 100));
        }
    }
    // Rotate case order each round; preserve every sample, not just the best.
    for (0..8) |round| {
        for (0..12) |position| {
            const mode = (position + round) % 12;
            const iterations: usize = if (mode == 2 or mode == 3 or mode == 5 or mode == 7 or mode == 9 or mode == 11) 500 else 2000;
            const start = std.Io.Clock.Timestamp.now(io, .awake);
            const result = switch (mode) {
                0 => try run(.codepoints, false, bytes, iterations),
                1 => try run(.spans, false, bytes, iterations),
                2 => try run(.codepoints, true, bytes, iterations),
                3 => try run(.spans, true, bytes, iterations),
                4 => try run(.bytes, false, bytes, iterations),
                5 => try run(.bytes, true, bytes, iterations),
                6 => try run(.raw_bytes, false, bytes, iterations),
                7 => try run(.raw_bytes, true, bytes, iterations),
                8 => try run(.measured, false, bytes, iterations),
                9 => try run(.measured, true, bytes, iterations),
                10 => try run(.remeasured, false, bytes, iterations),
                11 => try run(.remeasured, true, bytes, iterations),
                else => unreachable,
            };
            const ns = start.durationTo(std.Io.Clock.Timestamp.now(io, .awake)).raw.toNanoseconds();
            std.mem.doNotOptimizeAway(result);
            try out.print("{s},{d},{d},{d},{d},{d}\n", .{ name, mode, round, bytes.len, iterations, ns });
        }
    }
}

pub fn main(init: std.process.Init) !void {
    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    try stdout.interface.writeAll("corpus,mode,round,bytes,iterations,ns\n");
    try measure(init.io, &stdout.interface, "ascii", "The quick brown fox jumps over the lazy dog.\r\n" ** 64);
    try measure(init.io, &stdout.interface, "multilingual", "Cafe\u{301} Ελληνικά 日本語 👩‍👩‍👧‍👦 🇬🇷 " ** 32);
    try measure(init.io, &stdout.interface, "combining", "a\u{301}\u{327}\u{316}\u{300}\u{31d}\u{302}" ** 64);
    try stdout.interface.flush();
}
