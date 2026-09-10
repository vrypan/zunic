const std = @import("std");
const zunic = @import("zunic");
const Case = struct { name: []const u8, text: []const u8 };
const cases = [_]Case{
    .{ .name = "plain_ascii", .text = @embedFile("texts/plain_ascii.txt") },
    .{ .name = "plain_ascii_64k", .text = @embedFile("texts/plain_ascii_64k.txt") },
    .{ .name = "sparse_sgr", .text = @embedFile("texts/sparse_sgr.txt") },
    .{ .name = "dense_sgr", .text = @embedFile("texts/dense_sgr.txt") },
    .{ .name = "unicode", .text = @embedFile("texts/unicode.txt") },
    .{ .name = "osc_links", .text = @embedFile("texts/osc_links.txt") },
    .{ .name = "commands_only", .text = @embedFile("texts/commands_only.txt") },
    .{ .name = "custom_osc", .text = @embedFile("texts/custom_osc.txt") },
    .{ .name = "split_grapheme", .text = @embedFile("texts/split_grapheme.txt") },
    .{ .name = "long_osc", .text = @embedFile("texts/long_osc.txt") },
    .{ .name = "controls", .text = @embedFile("texts/controls.txt") },
    .{ .name = "invalid_utf8", .text = @embedFile("texts/invalid_utf8.txt") },
    .{ .name = "incomplete_csi", .text = @embedFile("texts/incomplete_csi.txt") },
    .{ .name = "incomplete_osc", .text = @embedFile("texts/incomplete_osc.txt") },
    .{ .name = "dcs", .text = @embedFile("texts/dcs.txt") },
    .{ .name = "c1", .text = @embedFile("texts/c1.txt") },
    .{ .name = "malformed_osc", .text = @embedFile("texts/malformed_osc.txt") },
    .{ .name = "empty", .text = @embedFile("texts/empty.txt") },
};
const sample_count = 15;
const target_ns: u64 = 50 * std.time.ns_per_ms;
const Result = struct { count: usize = 0, checksum: u64 = 0xcbf29ce484222325 };
var output_buffer: [65536]u8 = undefined;
fn consume(output: []const u8) Result {
    var result: Result = .{ .count = output.len };
    for (output) |byte| {
        result.checksum ^= byte;
        result.checksum *%= 0x100000001b3;
    }
    std.mem.doNotOptimizeAway(output);
    return result;
}
fn reused(bytes: []const u8) Result {
    var input = bytes;
    std.mem.doNotOptimizeAway(&input);
    return consume(zunic.terminal(input).stripAnsi(&output_buffer) catch unreachable);
}
fn allocated(bytes: []const u8) Result {
    var input = bytes;
    std.mem.doNotOptimizeAway(&input);
    const buffer = std.heap.smp_allocator.alloc(u8, input.len) catch unreachable;
    defer std.heap.smp_allocator.free(buffer);
    return consume(zunic.terminal(input).stripAnsi(buffer) catch unreachable);
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

pub fn main(init: std.process.Init) !void {
    var buffer: [4096]u8 = undefined;
    var file = std.Io.File.stdout().writer(init.io, &buffer);
    const out = &file.interface;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len == 1 or (args.len == 2 and (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h")))) {
        try out.writeAll(
            \\Usage: zunic-strip-ansi-bench MODE
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
    if (args.len == 2 and !std.mem.eql(u8, args[1], "--bench")) {
        const dump = std.mem.eql(u8, args[1], "--dump");
        if (!dump and !std.mem.eql(u8, args[1], "--check")) return error.UnexpectedArgument;
        for (cases) |case| {
            const output = try zunic.terminal(case.text).stripAnsi(&output_buffer);
            if (dump) {
                try out.print("case={s} input=", .{case.name});
                for (case.text) |byte| try out.print("{x:0>2}", .{byte});
                try out.writeAll("\nB ");
                for (output) |byte| try out.print("{x:0>2}", .{byte});
                try out.writeAll("\n");
            } else {
                const result = consume(output);
                try out.print("case={s} bytes={d} units={d} checksum={d}\n", .{ case.name, case.text.len, result.count, result.checksum });
            }
        }
        return out.flush();
    }
    if (args.len != 2 or !std.mem.eql(u8, args[1], "--bench")) return error.UnexpectedArgument;
    try out.writeAll("protocol=1 suite=strip_ansi peer=zunic engine=zunic unicode=not-applicable samples=15 calibration_ms=50 input=bytes consumption=bytes_fnv1\n");
    for (cases[0..10]) |case| {
        try measure(init.io, out, case, "zunic_reuse", reused);
        try measure(init.io, out, case, "zunic_alloc", allocated);
    }
    try out.flush();
}
test "allocation modes preserve exact bytes for all corpora" {
    for (cases) |case| {
        const expected = try zunic.terminal(case.text).stripAnsi(&output_buffer);
        const buffer = try std.testing.allocator.alloc(u8, case.text.len);
        defer std.testing.allocator.free(buffer);
        try std.testing.expectEqualSlices(u8, expected, try zunic.terminal(case.text).stripAnsi(buffer));
        try std.testing.expectEqualDeep(reused(case.text), allocated(case.text));
    }
}
