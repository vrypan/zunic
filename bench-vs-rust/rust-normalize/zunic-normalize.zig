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

fn printHex(out: *std.Io.Writer, bytes: []const u8) !void {
    for (bytes) |byte| try out.print("{x:0>2}", .{byte});
}

fn printDump(out: *std.Io.Writer, allocator: std.mem.Allocator) !void {
    for (cases) |case| inline for ([_]zunic.Form{ .nfc, .nfd }) |form| {
        const capacity = try zunic.text(case.text).normalizedLenBound(form);
        const buffer = try allocator.alloc(u8, capacity);
        defer allocator.free(buffer);
        const normalized = try zunic.text(case.text).normalize(form).writeTo(buffer);
        try out.print("case={s} form={s} input=", .{ case.name, @tagName(form) });
        try printHex(out, case.text);
        try out.writeAll(" hex=");
        try printHex(out, normalized);
        try out.writeByte('\n');
    };
    try out.flush();
}

pub fn main(init: std.process.Init) !void {
    var buffer: [64 * 1024]u8 = undefined;
    var file = std.Io.File.stdout().writer(init.io, &buffer);
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len == 1 or (args.len == 2 and (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h")))) {
        try file.interface.writeAll(
            \\Usage: zunic-normalize MODE
            \\
            \\Modes:
            \\  --bench  Run timing benchmarks
            \\  --dump   Print exact output records (bytes are hex-encoded)
            \\  --help, -h  Print this help
            \\
            \\No arguments prints help. Corpora are embedded at build time.
            \\
        );
        return file.interface.flush();
    }
    if (args.len != 2) return error.UnexpectedArgument;
    if (std.mem.eql(u8, args[1], "--dump")) return printDump(&file.interface, init.arena.allocator());
    if (std.mem.eql(u8, args[1], "--bench")) return printBench(init.io, &file.interface);
    return error.UnexpectedArgument;
}

const sample_count = 15;
const target_ns: u64 = 50 * std.time.ns_per_ms;

const BenchResult = struct { units: usize = 0, checksum: u64 = 0 };

fn normalizedScalars(bytes: []const u8, comptime form: zunic.Form) BenchResult {
    // Make the slice opaque before each traversal, including when the corpus
    // is embedded. The memory barrier forces a reload of its pointer/length.
    var input = bytes;
    std.mem.doNotOptimizeAway(&input);
    var iterator = zunic.text(input).normalize(form);
    var result: BenchResult = .{};
    while (iterator.next() catch unreachable) |scalar| {
        result.units += 1;
        result.checksum +%= scalar;
    }
    return result;
}

fn median(values: []u64) u64 {
    std.mem.sort(u64, values, {}, std.sort.asc(u64));
    return values[values.len / 2];
}

fn measure(io: std.Io, out: *std.Io.Writer, case: Case, comptime form: zunic.Form) !void {
    var iterations: usize = 1;
    while (true) {
        const start = std.Io.Clock.Timestamp.now(io, .awake);
        for (0..iterations) |_| std.mem.doNotOptimizeAway(normalizedScalars(case.text, form));
        const elapsed: u64 = @intCast(start.durationTo(std.Io.Clock.Timestamp.now(io, .awake)).raw.toNanoseconds());
        if (elapsed >= target_ns or iterations >= 1 << 20) break;
        const growth: usize = @intCast(target_ns / @max(elapsed, 1));
        iterations = @min(iterations *| @max(@as(usize, 2), growth), 1 << 20);
    }
    var samples: [sample_count]u64 = undefined;
    var result: BenchResult = .{};
    for (&samples) |*sample| {
        const start = std.Io.Clock.Timestamp.now(io, .awake);
        for (0..iterations) |_| {
            result = normalizedScalars(case.text, form);
            std.mem.doNotOptimizeAway(result);
        }
        const elapsed: u64 = @intCast(start.durationTo(std.Io.Clock.Timestamp.now(io, .awake)).raw.toNanoseconds());
        sample.* = elapsed / iterations;
    }
    try out.print("case={s} op={s} raw_samples={any}\n", .{ case.name, @tagName(form), samples });
    const per = median(&samples);
    var deviations: [sample_count]u64 = undefined;
    for (samples, &deviations) |sample, *deviation|
        deviation.* = if (sample > per) sample - per else per - sample;
    try out.print("case={s} op={s} bytes={d} units={d} iterations={d} ns={d} mad={d} checksum={d}\n", .{
        case.name, @tagName(form), case.text.len, result.units, iterations, per, median(&deviations), result.checksum,
    });
    try out.flush();
}

fn printBench(io: std.Io, out: *std.Io.Writer) !void {
    try out.writeAll("protocol=1 suite=normalize peer=zunic engine=zunic unicode=16.0.0 samples=15 calibration_ms=50 input=bytes consumption=scalar_sum_v1\n");
    for (cases) |case| {
        try measure(io, out, case, .nfc);
        try measure(io, out, case, .nfd);
    }
    try out.flush();
}

fn expectIdempotent(allocator: std.mem.Allocator, bytes: []const u8, comptime form: zunic.Form) !void {
    const first_capacity = try zunic.text(bytes).normalizedLenBound(form);
    const first = try allocator.alloc(u8, first_capacity);
    defer allocator.free(first);
    const normalized = try zunic.text(bytes).normalize(form).writeTo(first);
    const second_capacity = try zunic.text(normalized).normalizedLenBound(form);
    const second = try allocator.alloc(u8, second_capacity);
    defer allocator.free(second);
    try std.testing.expectEqualSlices(u8, normalized, try zunic.text(normalized).normalize(form).writeTo(second));
    try std.testing.expect(try zunic.text(normalized).isNormalized(form));
}

test "NFC and NFD are idempotent over shared corpora and Rust regression cases" {
    const regressions = [_][]const u8{
        "a\u{0301}",                          "\u{2126}", "\u{1E0B}\u{0323}", "\u{D4DB}",
        "a\u{0300}\u{0305}\u{0315}\u{05AE}b",
    };
    const allocator = std.testing.allocator;
    for (regressions) |bytes| inline for ([_]zunic.Form{ .nfc, .nfd }) |form|
        try expectIdempotent(allocator, bytes, form);
    inline for (cases) |case| inline for ([_]zunic.Form{ .nfc, .nfd }) |form|
        try expectIdempotent(allocator, case.text, form);
}
