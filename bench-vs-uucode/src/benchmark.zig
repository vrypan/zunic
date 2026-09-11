const std = @import("std");
const peer = @import("peer");

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
const Operation = enum { utf8, graphemes, measured, width };
const sample_count = 15;
const target_ns: u64 = 50 * std.time.ns_per_ms;

inline fn run(comptime operation: Operation, bytes: []const u8) peer.Stats {
    var input = bytes;
    std.mem.doNotOptimizeAway(&input);
    return switch (operation) {
        .utf8 => peer.utf8(input),
        .graphemes => peer.graphemes(input),
        .measured => peer.measured(input),
        .width => peer.width(input),
    };
}

fn median(values: []u64) u64 {
    std.mem.sort(u64, values, {}, std.sort.asc(u64));
    return values[values.len / 2];
}

fn measure(io: std.Io, out: *std.Io.Writer, case: Case, comptime operation: Operation) !void {
    std.mem.doNotOptimizeAway(run(operation, case.text));
    var iterations: usize = 1;
    while (true) {
        const start = std.Io.Clock.Timestamp.now(io, .awake);
        for (0..iterations) |_| std.mem.doNotOptimizeAway(run(operation, case.text));
        const elapsed: u64 = @intCast(start.durationTo(std.Io.Clock.Timestamp.now(io, .awake)).raw.toNanoseconds());
        if (elapsed >= target_ns or iterations >= 1 << 20) break;
        const growth: usize = @intCast(@max(@as(u64, 2), target_ns / @max(elapsed, 1)));
        iterations = @min(iterations *| growth, 1 << 20);
    }

    var samples: [sample_count]u64 = undefined;
    var result: peer.Stats = undefined;
    for (&samples) |*sample| {
        const start = std.Io.Clock.Timestamp.now(io, .awake);
        for (0..iterations) |_| {
            result = run(operation, case.text);
            std.mem.doNotOptimizeAway(result);
        }
        const elapsed: u64 = @intCast(start.durationTo(std.Io.Clock.Timestamp.now(io, .awake)).raw.toNanoseconds());
        sample.* = elapsed / iterations;
    }
    try out.print("case={s} op={s} raw_samples={any}\n", .{ case.name, @tagName(operation), samples });
    const per = median(&samples);
    var deviations: [sample_count]u64 = undefined;
    for (samples, &deviations) |sample, *deviation|
        deviation.* = if (sample > per) sample - per else per - sample;
    try out.print("case={s} op={s} bytes={d} units={d} iterations={d} ns={d} mad={d} checksum={d}\n", .{
        case.name,
        @tagName(operation),
        case.text.len,
        result.units,
        iterations,
        per,
        median(&deviations),
        result.checksum,
    });
    try out.flush();
}

fn dumpOne(out: *std.Io.Writer, case: Case, comptime operation: Operation) !void {
    const result = run(operation, case.text);
    try out.print("case={s} op={s} units={d} checksum={d} output=", .{
        case.name, @tagName(operation), result.units, result.checksum,
    });
    switch (operation) {
        .utf8 => try peer.dumpUtf8(out, case.text),
        .graphemes => try peer.dumpGraphemes(out, case.text),
        .measured => try peer.dumpMeasured(out, case.text),
        .width => try peer.dumpWidth(out, case.text),
    }
    try out.writeByte('\n');
}

fn printDump(out: *std.Io.Writer) !void {
    for (cases) |case| {
        try out.print("case={s} input=", .{case.name});
        for (case.text) |byte| try out.print("{x:0>2}", .{byte});
        try out.writeByte('\n');
        inline for (@typeInfo(Operation).@"enum".fields) |field|
            try dumpOne(out, case, @enumFromInt(field.value));
    }
    try out.flush();
}

pub fn main(init: std.process.Init) !void {
    var buffer: [64 * 1024]u8 = undefined;
    var file = std.Io.File.stdout().writer(init.io, &buffer);
    const out = &file.interface;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len == 1 or (args.len == 2 and (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h")))) {
        try out.print(
            \\Usage: {s}-bench MODE
            \\
            \\Modes:
            \\  --bench      Run timing benchmarks
            \\  --dump       Print exact output records
            \\  --help, -h   Print this help
            \\
            \\No arguments prints help. Corpora are embedded at build time.
            \\
        , .{peer.name});
        return out.flush();
    }
    if (args.len == 2 and std.mem.eql(u8, args[1], "--dump")) return printDump(out);
    if (args.len != 2 or !std.mem.eql(u8, args[1], "--bench")) return error.UnexpectedArgument;

    try out.print("protocol=1 suite=unicode peer={s} unicode={s} samples={d} calibration_ms={d} input=bytes consumption=operation_checksum_v1\n", .{
        peer.name, peer.unicode_version, sample_count, target_ns / std.time.ns_per_ms,
    });
    for (cases) |case| inline for (@typeInfo(Operation).@"enum".fields) |field|
        try measure(init.io, out, case, @enumFromInt(field.value));
    try out.flush();
}

test {
    // `benchmark.py --self-test` executes both adapters and verifies every
    // exact dump. This target still compiles the complete benchmark surface.
    _ = main;
}
