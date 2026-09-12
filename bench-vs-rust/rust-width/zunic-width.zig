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

fn textWidth(bytes: []const u8) usize {
    var input = bytes;
    std.mem.doNotOptimizeAway(&input);
    return zunic.text(input).width();
}

// Written out as a per-cluster loop rather than calling `width()` again, so
// this exercises the grapheme iterator path directly instead of whichever
// fast path `width()` takes for a given corpus.
fn graphemesWidth(bytes: []const u8) usize {
    var input = bytes;
    std.mem.doNotOptimizeAway(&input);
    var total: usize = 0;
    var iterator = zunic.text(input).graphemes().measured().iterator();
    while (iterator.next()) |span| total += @as(usize, span.columns);
    return total;
}

fn median(values: []u64) u64 {
    std.mem.sort(u64, values, {}, std.sort.asc(u64));
    return values[values.len / 2];
}

fn measure(io: std.Io, out: *std.Io.Writer, case: Case, op: []const u8, comptime pass: fn ([]const u8) usize) !void {
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
    var width: usize = 0;
    for (&samples) |*sample| {
        const start = std.Io.Clock.Timestamp.now(io, .awake);
        for (0..iterations) |_| {
            width = pass(case.text);
            std.mem.doNotOptimizeAway(width);
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
        case.name, op, case.text.len, width, iterations, per, mad, width,
    });
    try out.flush();
}

fn printDump(out: *std.Io.Writer) !void {
    for (cases) |case| {
        try out.print("case={s} input=", .{case.name});
        for (case.text) |byte| try out.print("{x:0>2}", .{byte});
        try out.print(" width={d}\n", .{zunic.text(case.text).width()});
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
            \\Usage: zunic-width-bench MODE
            \\
            \\Modes:
            \\  --bench  Run timing benchmarks
            \\  --dump   Print exact output records
            \\  --help, -h  Print this help
            \\
            \\No arguments prints help. Corpora are embedded at build time.
            \\
        );
        return out.flush();
    }
    if (args.len == 2 and std.mem.eql(u8, args[1], "--dump")) return printDump(out);
    if (args.len != 2 or !std.mem.eql(u8, args[1], "--bench")) return error.UnexpectedArgument;

    try out.print("protocol=1 suite=width peer=zunic engine=zunic unicode=17.0.0 samples={d} calibration_ms={d} input=bytes consumption=width_sum_v1\n", .{ sample_count, target_ns / std.time.ns_per_ms });
    for (cases) |case| {
        try measure(init.io, out, case, "zunic_width", textWidth);
    }
    try out.flush();
}

test "the batch and per-cluster width paths agree on every shared corpus" {
    inline for (cases) |case| {
        try std.testing.expectEqual(textWidth(case.text), graphemesWidth(case.text));
    }
}
