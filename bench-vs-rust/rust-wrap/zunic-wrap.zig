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
const width = 80;
const viewport = 24;
const sample_count = 15;
const target_ns: u64 = 50 * std.time.ns_per_ms;

var allocator: std.mem.Allocator = std.heap.smp_allocator;

const Result = struct { count: usize = 0, checksum: u64 = 0xcbf29ce484222325 };

fn wrapPass(bytes: []const u8, comptime limit: usize) Result {
    var input = bytes;
    std.mem.doNotOptimizeAway(&input);
    var iterator = (zunic.text(input).wrap(.{ .max_columns = width, .overflow = .grapheme }) catch unreachable).iterator();
    var result: Result = .{};
    while (result.count < limit) {
        const line = iterator.next() orelse break;
        checksumLine(&result.checksum, line, input);
        result.count += 1;
    }
    return result;
}
fn wrapIterate(bytes: []const u8) Result {
    return wrapPass(bytes, std.math.maxInt(usize));
}
fn wrapFirst24(bytes: []const u8) Result {
    return wrapPass(bytes, viewport);
}

fn wrapCollect(bytes: []const u8) Result {
    var input = bytes;
    std.mem.doNotOptimizeAway(&input);
    var lines: std.ArrayList(zunic.Line) = .empty;
    defer lines.deinit(allocator);
    var iterator = (zunic.text(input).wrap(.{ .max_columns = width, .overflow = .grapheme }) catch unreachable).iterator();
    while (iterator.next()) |line| lines.append(allocator, line) catch unreachable;
    var result: Result = .{ .count = lines.items.len };
    for (lines.items) |line| checksumLine(&result.checksum, line, input);
    std.mem.doNotOptimizeAway(lines.items);
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
    var lines: Result = .{};
    for (&samples) |*sample| {
        const start = std.Io.Clock.Timestamp.now(io, .awake);
        for (0..iterations) |_| {
            lines = pass(case.text);
            std.mem.doNotOptimizeAway(lines);
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
        case.name, op, case.text.len, lines.count, iterations, per, mad, lines.checksum,
    });
    try out.flush();
}

fn checksumLine(hash: *u64, line: zunic.Line, text: []const u8) void {
    for (text[line.start.value..line.end.value]) |byte| {
        hash.* ^= byte;
        hash.* *%= 0x100000001b3;
    }
    hash.* ^= 0xff;
    hash.* *%= 0x100000001b3;
}

fn printChecks(out: *std.Io.Writer) !void {
    for (cases) |case| {
        var iterator = (zunic.text(case.text).wrap(.{ .max_columns = width, .overflow = .grapheme }) catch unreachable).iterator();
        var hash: u64 = 0xcbf29ce484222325;
        var lines: usize = 0;
        while (iterator.next()) |line| {
            checksumLine(&hash, line, case.text);
            lines += 1;
        }
        try out.print("case={s} bytes={d} lines={d} checksum={x:0>16}\n", .{ case.name, case.text.len, lines, hash });
    }
    try out.flush();
}

fn printDump(out: *std.Io.Writer) !void {
    for (cases) |case| {
        try out.print("case={s} input=", .{case.name});
        for (case.text) |byte| try out.print("{x:0>2}", .{byte});
        try out.writeAll("\n");
        var it = (zunic.text(case.text).wrap(.{ .max_columns = width, .overflow = .grapheme }) catch unreachable).iterator();
        while (it.next()) |line| {
            try out.writeAll("L ");
            for (case.text[line.start.value..line.end.value]) |byte| try out.print("{x:0>2}", .{byte});
            try out.writeAll("\n");
        }
    }
    try out.flush();
}

pub fn main(init: std.process.Init) !void {
    allocator = std.heap.smp_allocator;
    var buffer: [4096]u8 = undefined;
    var file = std.Io.File.stdout().writer(init.io, &buffer);
    const out = &file.interface;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len == 1 or (args.len == 2 and (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h")))) {
        try out.writeAll(
            \\Usage: zunic-wrap-bench MODE
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

    try out.print("protocol=1 suite=wrap peer=zunic engine=zunic unicode=16.0.0 samples={d} calibration_ms={d} input=bytes consumption=line_bytes_fnv1 width={d}\n", .{ sample_count, target_ns / std.time.ns_per_ms, width });
    for (cases) |case| {
        try measure(init.io, out, case, "zunic_iterate", wrapIterate);
        try measure(init.io, out, case, "zunic_collect", wrapCollect);
        try measure(init.io, out, case, "zunic_first24", wrapFirst24);
    }
    try out.flush();
}

test "wraps every shared corpus within the requested width" {
    inline for (cases) |case| {
        var iterator = (try zunic.text(case.text).wrap(.{ .max_columns = width, .overflow = .grapheme })).iterator();
        var previous_end: usize = 0;
        var lines: usize = 0;
        while (iterator.next()) |line| {
            try std.testing.expect(line.start.value >= previous_end);
            try std.testing.expect(line.end.value >= line.start.value);
            try std.testing.expect(line.end.value <= case.text.len);
            try std.testing.expect(line.columns.value <= width);
            previous_end = line.end.value;
            lines += 1;
        }
        try std.testing.expect(lines > 0);
    }
}

test "viewport operation reports at most 24 lines" {
    inline for (cases) |case|
        try std.testing.expectEqual(@min(wrapIterate(case.text).count, viewport), wrapFirst24(case.text).count);
}

test "collection preserves the complete consumed line output" {
    inline for (cases) |case| try std.testing.expectEqualDeep(wrapIterate(case.text), wrapCollect(case.text));
}
