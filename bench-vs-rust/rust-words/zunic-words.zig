const std = @import("std");
const zunic = @import("zunic");

const Case = struct { name: []const u8, text: []const u8 };
const cases = [_]Case{
    .{ .name = "arabic", .text = @embedFile("texts/arabic.txt") },
    .{ .name = "hindi", .text = @embedFile("texts/hindi.txt") },
    .{ .name = "korean", .text = @embedFile("texts/korean.txt") },
    .{ .name = "russian", .text = @embedFile("texts/russian.txt") },
    .{ .name = "source_code", .text = @embedFile("texts/source_code.txt") },
    .{ .name = "english", .text = @embedFile("texts/english.txt") },
    .{ .name = "japanese", .text = @embedFile("texts/japanese.txt") },
    .{ .name = "mandarin", .text = @embedFile("texts/mandarin.txt") },
};
const sample_count = 15;
const target_ns: u64 = 50 * std.time.ns_per_ms;

// Only `zunic_word_bounds_collect` allocates, and only to hold borrowed items.
// Defaulted here rather than assigned in main so the tests, which never run
// main, do not read an undefined allocator.
var allocator: std.mem.Allocator = std.heap.smp_allocator;

const Result = struct {
    count: usize = 0,
    checksum: u64 = 0,
    fn add(self: *Result, start: usize, end: usize) void {
        self.count += 1;
        self.checksum = self.checksum *% 31 +% start;
        self.checksum = self.checksum *% 31 +% end;
    }
};

fn wordBounds(bytes: []const u8) Result {
    var input = bytes;
    std.mem.doNotOptimizeAway(&input);
    var iterator = zunic.text(input).wordBounds().iterator();
    var result: Result = .{};
    while (iterator.next()) |segment| result.add(segment.start.value, segment.end.value);
    return result;
}

fn wordBoundsCollect(bytes: []const u8) Result {
    var input = bytes;
    std.mem.doNotOptimizeAway(&input);
    var items: std.ArrayList(zunic.WordBound) = .empty;
    defer items.deinit(allocator);
    var iterator = zunic.text(input).wordBounds().iterator();
    while (iterator.next()) |segment| items.append(allocator, segment) catch unreachable;
    var result: Result = .{};
    for (items.items) |segment| result.add(segment.start.value, segment.end.value);
    std.mem.doNotOptimizeAway(items.items);
    return result;
}

fn words(bytes: []const u8) Result {
    var input = bytes;
    std.mem.doNotOptimizeAway(&input);
    var iterator = zunic.text(input).wordBounds().iterator();
    var result: Result = .{};
    while (iterator.next()) |segment| {
        if (segment.is_word) result.add(segment.start.value, segment.end.value);
    }
    return result;
}

fn median(values: []u64) u64 {
    std.mem.sort(u64, values, {}, std.sort.asc(u64));
    return values[values.len / 2];
}

fn measure(io: std.Io, out: *std.Io.Writer, case: Case, op: []const u8, comptime pass: fn ([]const u8) Result) !void {
    std.mem.doNotOptimizeAway(pass(case.text));
    var iterations: usize = 1;
    while (true) {
        const start = std.Io.Clock.Timestamp.now(io, .awake);
        for (0..iterations) |_| std.mem.doNotOptimizeAway(pass(case.text));
        const elapsed: u64 = @intCast(start.durationTo(std.Io.Clock.Timestamp.now(io, .awake)).raw.toNanoseconds());
        if (elapsed >= target_ns or iterations >= 1 << 20) break;
        const growth: usize = @intCast(@max(@as(u64, 2), target_ns / @max(elapsed, 1)));
        iterations = @min(iterations *| growth, 1 << 20);
    }

    var samples: [sample_count]u64 = undefined;
    var items: Result = .{};
    for (&samples) |*sample| {
        const start = std.Io.Clock.Timestamp.now(io, .awake);
        for (0..iterations) |_| {
            items = pass(case.text);
            std.mem.doNotOptimizeAway(items);
        }
        const elapsed: u64 = @intCast(start.durationTo(std.Io.Clock.Timestamp.now(io, .awake)).raw.toNanoseconds());
        sample.* = elapsed / iterations;
    }
    try out.print("case={s} op={s} raw_samples={any}\n", .{ case.name, op, samples });
    const per = median(&samples);
    var deviations: [sample_count]u64 = undefined;
    for (samples, &deviations) |sample, *deviation|
        deviation.* = if (sample > per) sample - per else per - sample;
    const mad = median(&deviations);
    try out.print("case={s} op={s} bytes={d} units={d} iterations={d} ns={d} mad={d} checksum={d}\n", .{
        case.name, op, case.text.len, items.count, iterations, per, mad, items.checksum,
    });
    try out.flush();
}

/// Byte-for-byte the mix in src/benchmark.zig, mirrored on the Rust side, so
/// a checksum difference means a segmentation difference and nothing else.
fn mix(state: u64, value: u64) u64 {
    return (state ^ (value +% 0x9e3779b97f4a7c15)) *% 0xbf58476d1ce4e5b9;
}

const Checks = struct { segments: usize, words: usize, bounds: u64, flags: u64 };

fn checksums(text: []const u8) Checks {
    var result: Checks = .{ .segments = 0, .words = 0, .bounds = 0xcbf29ce484222325, .flags = 0xcbf29ce484222325 };
    var iterator = zunic.text(text).wordBounds().iterator();
    while (iterator.next()) |segment| {
        result.bounds = mix(mix(result.bounds, segment.start.value), segment.end.value);
        result.flags = mix(result.flags, @intFromBool(segment.is_word));
        result.segments += 1;
        if (segment.is_word) result.words += 1;
    }
    return result;
}

fn printChecks(out: *std.Io.Writer) !void {
    for (cases) |case| {
        const check = checksums(case.text);
        try out.print("case={s} bytes={d} segments={d} words={d} bounds_checksum={x:0>16} flag_checksum={x:0>16}\n", .{
            case.name, case.text.len, check.segments, check.words, check.bounds, check.flags,
        });
    }
    try out.flush();
}

fn printDump(out: *std.Io.Writer) !void {
    for (cases) |case| {
        try out.print("case={s} input=", .{case.name});
        for (case.text) |byte| try out.print("{x:0>2}", .{byte});
        try out.writeAll("\n");
        try out.print("case={s} bytes={d}\n", .{ case.name, case.text.len });
        var iterator = zunic.text(case.text).wordBounds().iterator();
        while (iterator.next()) |segment|
            try out.print("S {d} {d} {d}\n", .{ segment.start.value, segment.end.value, @intFromBool(segment.is_word) });
    }
    try out.flush();
}

pub fn main(init: std.process.Init) !void {
    var buffer: [64 * 1024]u8 = undefined;
    var file = std.Io.File.stdout().writer(init.io, &buffer);
    const out = &file.interface;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len == 1 or (args.len == 2 and (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h")))) {
        try out.writeAll(
            \\Usage: zunic-words-bench MODE
            \\
            \\Modes:
            \\  --bench  Run timing benchmarks
            \\  --dump   Print exact output records (bytes are hex-encoded)
            \\  --check  Print output counts and checksums
            \\  --help, -h  Print this help
            \\
            \\No arguments prints help. Corpora are embedded at build time.
            \\
        );
        return out.flush();
    }
    if (args.len == 2 and std.mem.eql(u8, args[1], "--check")) return printChecks(out);
    if (args.len == 2 and std.mem.eql(u8, args[1], "--dump")) return printDump(out);
    if (args.len != 2 or !std.mem.eql(u8, args[1], "--bench")) return error.UnexpectedArgument;

    try out.print("protocol=1 suite=words peer=zunic engine=zunic unicode=16.0.0 samples={d} calibration_ms={d} input=bytes consumption=range_checksum_v1\n", .{ sample_count, target_ns / std.time.ns_per_ms });
    for (cases) |case| {
        try measure(init.io, out, case, "zunic_word_bounds", wordBounds);
        try measure(init.io, out, case, "zunic_word_bounds_collect", wordBoundsCollect);
        try measure(init.io, out, case, "zunic_words", words);
    }
    try out.flush();
}

test "word bounds partition every shared corpus" {
    inline for (cases) |case| {
        var iterator = zunic.text(case.text).wordBounds().iterator();
        var cursor: usize = 0;
        var segments: usize = 0;
        while (iterator.next()) |segment| {
            try std.testing.expectEqual(cursor, segment.start.value);
            try std.testing.expect(segment.end.value > segment.start.value);
            cursor = segment.end.value;
            segments += 1;
        }
        try std.testing.expectEqual(case.text.len, cursor);
        try std.testing.expect(segments > 0);
    }
}

test "the measured operations agree on item counts" {
    inline for (cases) |case| {
        const check = checksums(case.text);
        try std.testing.expectEqualDeep(wordBounds(case.text), wordBoundsCollect(case.text));
        try std.testing.expectEqual(check.segments, wordBounds(case.text).count);
        try std.testing.expectEqual(check.segments, wordBoundsCollect(case.text).count);
        try std.testing.expectEqual(check.words, words(case.text).count);
    }
}

test "the flag agrees with ASCII letters and digits wherever they decide it" {
    // The word table is internal to the package, so this cannot recompute the
    // full predicate; that job belongs to differential.py, which checks every
    // flag against unicode-segmentation. What it can pin from outside is the
    // uncontroversial half: an ASCII letter or digit is Alphabetic or Nd, so a
    // segment containing one must be flagged.
    inline for (cases) |case| {
        var iterator = zunic.text(case.text).wordBounds().iterator();
        while (iterator.next()) |segment| {
            const bytes = case.text[segment.start.value..segment.end.value];
            for (bytes) |byte| {
                if (std.ascii.isAlphanumeric(byte)) {
                    try std.testing.expect(segment.is_word);
                    break;
                }
            }
        }
    }
}
