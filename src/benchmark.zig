const std = @import("std");
const zunic = @import("zunic");

const harness_version = "2";
const sample_count = 7;
const Corpus = struct { name: []const u8, seed: []const u8, length: usize };
const WrapCase = struct { name: []const u8, corpus: Corpus, max_columns: usize, overflow: zunic.wrap.Overflow, max_lines: ?usize = null };

const legacy_corpora = [_]Corpus{
    .{ .name = "ascii", .seed = "The quick brown fox jumps over the lazy dog. ", .length = 96 },
    .{ .name = "combining", .seed = "Cafe\xcc\x81 nai\xcc\x88ve coo\xcc\x88perate. ", .length = 96 },
    .{ .name = "cjk", .seed = "日本語の文章と漢字を測定します。 ", .length = 96 },
    .{ .name = "emoji", .seed = "👩‍👩‍👧‍👦 🇬🇷 👋🏿 ", .length = 96 },
    .{ .name = "malformed", .seed = "valid \xff bytes \xc0\x80 remain bounded ", .length = 96 },
};

const wrap_cases = [_]WrapCase{
    .{ .name = "ascii-words-4k-grapheme-full", .corpus = .{ .name = "ascii-words", .seed = "alpha beta gamma delta epsilon zeta eta theta ", .length = 4096 }, .max_columns = 40, .overflow = .grapheme },
    .{ .name = "ascii-words-4k-allow-full", .corpus = .{ .name = "ascii-words", .seed = "alpha beta gamma delta epsilon zeta eta theta ", .length = 4096 }, .max_columns = 40, .overflow = .allow },
    .{ .name = "prose-64-grapheme-full", .corpus = .{ .name = "prose", .seed = "A paragraph has spaces, punctuation, numbers 123, and quoted words. ", .length = 96 }, .max_columns = 1, .overflow = .grapheme },
    .{ .name = "prose-4k-allow-full", .corpus = .{ .name = "prose", .seed = "A paragraph has spaces, punctuation, numbers 123, and quoted words. ", .length = 4096 }, .max_columns = 40, .overflow = .allow },
    .{ .name = "greek-4k-grapheme-full", .corpus = .{ .name = "greek", .seed = "Καλημέρα cafe\xcc\x81 — λέξεις και τόνοι. ", .length = 4096 }, .max_columns = 80, .overflow = .grapheme },
    .{ .name = "cjk-4k-allow-full", .corpus = .{ .name = "cjk", .seed = "日本語の文章と漢字を測定します。 ", .length = 4096 }, .max_columns = 40, .overflow = .allow },
    .{ .name = "emoji-4k-grapheme-24-lines", .corpus = .{ .name = "emoji", .seed = "👩‍👩‍👧‍👦 🇬🇷 👋🏿 ", .length = 4096 }, .max_columns = 40, .overflow = .grapheme, .max_lines = 24 },
    .{ .name = "hard-breaks-4k-allow-24-lines", .corpus = .{ .name = "hard", .seed = "alpha\nβeta\x0c界\xc2\x85emoji👩‍👩‍👧‍👦 ", .length = 4096 }, .max_columns = 80, .overflow = .allow, .max_lines = 24 },
    .{ .name = "long-word-4k-grapheme-full", .corpus = .{ .name = "word", .seed = "supercalifragilisticexpialidocious", .length = 4096 }, .max_columns = 40, .overflow = .grapheme },
    .{ .name = "zero-width-4k-allow-full", .corpus = .{ .name = "zero", .seed = "e\xcc\x81\xcc\x81\xcc\x81\xcc\x81", .length = 4096 }, .max_columns = 1, .overflow = .allow },
    .{ .name = "malformed-4k-grapheme-full", .corpus = .{ .name = "malformed", .seed = "ok \xff \xc0\x80 text ", .length = 4096 }, .max_columns = 40, .overflow = .grapheme },
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    const smoke = args.len > 1 and std.mem.eql(u8, args[1], "--smoke");
    const target_bytes: usize = if (smoke) 64 * 1024 else 4 * 1024 * 1024;
    var output_buffer: [4096]u8 = undefined;
    var output_file = std.Io.File.stdout().writer(io, &output_buffer);
    const output = &output_file.interface;
    try output.print("zunic-benchmark harness_version={s} target_bytes={d} samples={d} smoke={any} wrap_fast_path={s}\n", .{ harness_version, target_bytes, sample_count, smoke, @tagName(zunic.build_options.wrap_fast_path) });
    for (legacy_corpora) |corpus| {
        const text = try makeCorpus(allocator, corpus);
        try printSamples(output, corpus.name, "utf8", text, target_bytes, utf8Checksum, io);
        try printSamples(output, corpus.name, "grapheme", text, target_bytes, graphemeChecksum, io);
        try printSamples(output, corpus.name, "width", text, target_bytes, widthChecksum, io);
        try printSamples(output, corpus.name, "line_break", text, target_bytes, lineBreakChecksum, io);
    }
    for (wrap_cases) |case| try printWrapSamples(output, case, try makeCorpus(allocator, case.corpus), target_bytes, io);
    try output.flush();
}

fn makeCorpus(allocator: std.mem.Allocator, corpus: Corpus) ![]u8 {
    const text = try allocator.alloc(u8, corpus.length);
    for (text, 0..) |*byte, index| byte.* = corpus.seed[index % corpus.seed.len];
    return text;
}

fn printSamples(output: *std.Io.Writer, corpus: []const u8, operation: []const u8, text: []u8, target_bytes: usize, comptime checksumFn: fn ([]const u8) u64, io: std.Io) !void {
    const iterations = @max(@as(usize, 1), target_bytes / text.len);
    std.mem.doNotOptimizeAway(checksumFn(text));
    for (0..sample_count) |_| {
        const start = std.Io.Clock.Timestamp.now(io, .awake);
        var checksum: u64 = 0;
        for (0..iterations) |_| {
            std.mem.doNotOptimizeAway(text);
            checksum +%= checksumFn(text);
        }
        std.mem.doNotOptimizeAway(checksum);
        const elapsed = start.durationTo(std.Io.Clock.Timestamp.now(io, .awake)).raw.toNanoseconds();
        try printSample(output, corpus, operation, "full", text.len, iterations, elapsed, checksum, text.len * iterations, null, null);
    }
}

fn printWrapSamples(output: *std.Io.Writer, case: WrapCase, text: []u8, target_bytes: usize, io: std.Io) !void {
    const iterations = @max(@as(usize, 1), target_bytes / text.len);
    std.mem.doNotOptimizeAway(wrapChecksum(text, case));
    for (0..sample_count) |_| {
        const start = std.Io.Clock.Timestamp.now(io, .awake);
        var checksum: u64 = 0;
        var lines: usize = 0;
        var emitted: usize = 0;
        for (0..iterations) |_| {
            const result = wrapChecksum(text, case);
            checksum +%= result.checksum;
            lines += result.lines;
            emitted += result.emitted_bytes;
        }
        std.mem.doNotOptimizeAway(checksum);
        const elapsed = start.durationTo(std.Io.Clock.Timestamp.now(io, .awake)).raw.toNanoseconds();
        try printSample(output, case.name, "wrap", if (case.max_lines == null) "full" else "viewport", text.len, iterations, elapsed, checksum, emitted, lines, case.max_columns);
    }
}

fn printSample(output: *std.Io.Writer, case: []const u8, operation: []const u8, traversal: []const u8, input_bytes: usize, iterations: usize, elapsed_ns: i96, checksum: u64, work_bytes: usize, lines: ?usize, max_columns: ?usize) !void {
    const rate: f64 = if (elapsed_ns <= 0) 0 else @as(f64, @floatFromInt(work_bytes)) / 1048576.0 / (@as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0);
    try output.print("case={s} operation={s} traversal={s} input_bytes={d} iterations={d} work_bytes={d} elapsed_ns={d} checksum={d} mib_per_s={d:.2}", .{ case, operation, traversal, input_bytes, iterations, work_bytes, elapsed_ns, checksum, rate });
    if (lines) |value| try output.print(" lines={d}", .{value});
    if (max_columns) |value| try output.print(" max_columns={d}", .{value});
    try output.writeAll("\n");
}

fn mix(state: u64, value: u64) u64 {
    return (state ^ (value +% 0x9e3779b97f4a7c15)) *% 0xbf58476d1ce4e5b9;
}
fn utf8Checksum(text: []const u8) u64 {
    var pos: usize = 0;
    var sum: u64 = 0xcbf29ce484222325;
    while (pos < text.len) {
        const step = zunic.utf8.step(text[pos..]);
        sum = mix(sum, step.len);
        sum = mix(sum, step.cp orelse 0xffff_ffff);
        pos += step.len;
    }
    return sum;
}
fn graphemeChecksum(text: []const u8) u64 {
    var it = zunic.grapheme.iterator(text);
    var sum: u64 = 0xcbf29ce484222325;
    while (it.next()) |span| {
        sum = mix(sum, span.start);
        sum = mix(sum, span.end);
    }
    return sum;
}
fn widthChecksum(text: []const u8) u64 {
    return mix(0xcbf29ce484222325, zunic.width.textWidth(text));
}
fn lineBreakChecksum(text: []const u8) u64 {
    var it = zunic.line_break.iterator(text);
    var sum: u64 = 0xcbf29ce484222325;
    while (it.next()) |boundary| {
        sum = mix(sum, boundary.offset);
        sum = mix(sum, @intFromEnum(boundary.opportunity));
    }
    return sum;
}
const WrapResult = struct { checksum: u64, lines: usize, emitted_bytes: usize };
fn wrapChecksum(text: []const u8, case: WrapCase) WrapResult {
    var it = zunic.wrap.iterator(text, .{ .max_columns = case.max_columns, .overflow = case.overflow }) catch unreachable;
    var sum: u64 = 0xcbf29ce484222325;
    var lines: usize = 0;
    var emitted: usize = 0;
    while (it.next()) |line| {
        sum = mix(sum, line.start);
        sum = mix(sum, line.end);
        sum = mix(sum, line.columns);
        lines += 1;
        emitted += line.end - line.start;
        if (case.max_lines) |limit| if (lines == limit) break;
    }
    return .{ .checksum = sum, .lines = lines, .emitted_bytes = emitted };
}
