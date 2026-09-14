//! Run with `zig build benchmark-reader -Doptimize=ReleaseFast`.
//! Counts and span checksums are checked against slice iteration before timing.
const std = @import("std");
const zunic = @import("zunic");

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

fn scan(comptime graphemes: bool, input: *std.Io.Reader) !Result {
    var result: Result = .{};
    if (graphemes) {
        var it = zunic.reader(input).graphemes();
        while (try it.next()) |update| {
            if (update.point) |point| result.point(point.value, update.grapheme.end);
            result.span(update.grapheme.start, update.grapheme.end, update.starts_new, update.is_final);
        }
    } else {
        var it = zunic.reader(input).codepoints();
        while (try it.next()) |point| result.point(point.value, it.offset);
    }
    return result;
}

fn run(comptime graphemes: bool, comptime chunked: bool, bytes: []const u8, iterations: usize) !Result {
    var total: Result = .{};
    for (0..iterations) |_| {
        std.mem.doNotOptimizeAway(bytes);
        var storage: [4]u8 = undefined;
        var short = Chunked.init(bytes, &storage);
        var fixed: std.Io.Reader = .fixed(bytes);
        const result = try scan(graphemes, if (chunked) &short.interface else &fixed);
        total.scalars +%= result.scalars;
        total.boundaries +%= result.boundaries;
        total.finals +%= result.finals;
        total.checksum +%= result.checksum;
    }
    return total;
}

fn expected(comptime graphemes: bool, bytes: []const u8) !Result {
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
            result.point(value, offset);
            if (graphemes) result.span(last_start, offset, boundary, false);
        }
    }
    if (graphemes and bytes.len != 0) result.span(last_start, bytes.len, false, true);
    return result;
}

fn measure(io: std.Io, out: *std.Io.Writer, name: []const u8, bytes: []const u8) !void {
    inline for (.{ false, true }) |graphemes| {
        const oracle = try expected(graphemes, bytes);
        inline for (.{ false, true }) |chunked| {
            if (!std.meta.eql(oracle, try run(graphemes, chunked, bytes, 1))) return error.BenchmarkMismatch;
            std.mem.doNotOptimizeAway(try run(graphemes, chunked, bytes, 100));
        }
    }
    // Rotate case order each round; preserve every sample, not just the best.
    for (0..8) |round| {
        for (0..4) |position| {
            const mode = (position + round) % 4;
            const iterations: usize = if (mode >= 2) 500 else 2000;
            const start = std.Io.Clock.Timestamp.now(io, .awake);
            const result = switch (mode) {
                0 => try run(false, false, bytes, iterations),
                1 => try run(true, false, bytes, iterations),
                2 => try run(false, true, bytes, iterations),
                3 => try run(true, true, bytes, iterations),
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
