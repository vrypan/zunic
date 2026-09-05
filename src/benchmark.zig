const std = @import("std");
const zunic = @import("zunic");

const Sample = struct {
    corpus: []const u8,
    operation: []const u8,
    bytes: usize,
    iterations: usize,
    elapsed_ns: i96,
    checksum: u64,
};

const corpora = [_]struct { name: []const u8, text: []const u8 }{
    .{ .name = "ascii", .text = "The quick brown fox jumps over the lazy dog. " },
    .{ .name = "combining", .text = "Cafe\xcc\x81 nai\xcc\x88ve coo\xcc\x88perate. " },
    .{ .name = "cjk", .text = "日本語の文章と漢字を測定します。 " },
    .{
        .name = "emoji",
        .text = "👩‍👩‍👧‍👦 🇬🇷 👋🏿 ",
    },
    .{
        .name = "malformed",
        .text = "valid \xff bytes \xc0\x80 remain bounded ",
    },
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const target_bytes: usize = if (args.len > 1 and std.mem.eql(u8, args[1], "--smoke")) 64 * 1024 else 16 * 1024 * 1024;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_file.interface;
    try stdout.print("zunic benchmark target_bytes={d} samples=5\n", .{target_bytes});

    for (corpora) |corpus| {
        try printSamples(stdout, corpus.name, "utf8", corpus.text, target_bytes, utf8Checksum, io);
        try printSamples(stdout, corpus.name, "grapheme", corpus.text, target_bytes, graphemeChecksum, io);
        try printSamples(stdout, corpus.name, "width", corpus.text, target_bytes, widthChecksum, io);
        try printSamples(stdout, corpus.name, "line_break", corpus.text, target_bytes, lineBreakChecksum, io);
        try printSamples(stdout, corpus.name, "wrap", corpus.text, target_bytes, wrapChecksum, io);
    }
    try stdout.flush();
}

fn printSamples(
    stdout: *std.Io.Writer,
    corpus: []const u8,
    operation: []const u8,
    text: []const u8,
    target_bytes: usize,
    comptime checksumFn: fn ([]const u8) u64,
    io: std.Io,
) !void {
    const iterations = @max(@as(usize, 1), target_bytes / text.len);
    _ = checksumFn(text);
    for (0..5) |_| {
        const start = std.Io.Clock.Timestamp.now(io, .awake);
        var checksum: u64 = 0;
        for (0..iterations) |_| {
            std.mem.doNotOptimizeAway(&text);
            checksum +%= checksumFn(text);
        }
        std.mem.doNotOptimizeAway(&checksum);
        const end = std.Io.Clock.Timestamp.now(io, .awake);
        const elapsed_ns = start.durationTo(end).raw.toNanoseconds();
        const bytes = text.len * iterations;
        const mib_per_second: f64 = if (elapsed_ns <= 0) 0 else @as(f64, @floatFromInt(bytes)) / 1048576.0 / (@as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0);
        try stdout.print("corpus={s} operation={s} input_bytes={d} iterations={d} processed_bytes={d} elapsed_ns={d} checksum={d} mib_per_s={d:.2}\n", .{ corpus, operation, text.len, iterations, bytes, elapsed_ns, checksum, mib_per_second });
    }
}

fn utf8Checksum(text: []const u8) u64 {
    var pos: usize = 0;
    var sum: u64 = 0;
    while (pos < text.len) {
        const step = zunic.utf8.step(text[pos..]);
        pos += step.len;
        sum +%= step.len + @as(u64, step.cp orelse 0);
    }
    return sum;
}

fn graphemeChecksum(text: []const u8) u64 {
    var it = zunic.grapheme.iterator(text);
    var sum: u64 = 0;
    while (it.next()) |span| sum +%= span.end - span.start;
    return sum;
}

fn widthChecksum(text: []const u8) u64 {
    return zunic.width.textWidth(text);
}

fn lineBreakChecksum(text: []const u8) u64 {
    var it = zunic.line_break.iterator(text);
    var sum: u64 = 0;
    while (it.next()) |boundary| sum +%= boundary.offset + @intFromEnum(boundary.opportunity);
    return sum;
}

fn wrapChecksum(text: []const u8) u64 {
    var it = zunic.wrap.iterator(text, .{ .max_columns = 40 }) catch unreachable;
    var sum: u64 = 0;
    while (it.next()) |line| sum +%= line.end - line.start + line.columns;
    return sum;
}
