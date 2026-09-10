const std = @import("std");
const internal = @import("internal");
const scalar = internal.scalar;
const lb = internal.line_break;
const zunic = @import("zunic");
const cases = .{
    .{ "arabic", @embedFile("texts/arabic.txt") },
    .{ "hindi", @embedFile("texts/hindi.txt") },
    .{ "korean", @embedFile("texts/korean.txt") },
    .{ "russian", @embedFile("texts/russian.txt") },
    .{ "source_code", @embedFile("texts/source_code.txt") },
    .{ "english", @embedFile("texts/english.txt") },
    .{ "japanese", @embedFile("texts/japanese.txt") },
    .{ "mandarin", @embedFile("texts/mandarin.txt") },
};
var tokens: [60000]scalar.ClassifiedToken = undefined;
var token_count: usize = 0;

const Result = struct {
    count: usize = 0,
    checksum: u64 = 0,
    fn add(self: *Result, offset: usize, status: u64) void {
        self.count += 1;
        self.checksum = self.checksum *% 31 +% offset;
        self.checksum = self.checksum *% 31 +% status;
    }
};
fn kind(op: lb.Opportunity) u64 {
    return switch (op) {
        .prohibited => 0,
        .allowed => 1,
        .mandatory => 2,
    };
}

fn classify(bytes: []const u8) Result {
    var input = bytes;
    std.mem.doNotOptimizeAway(&input);
    var classifier = scalar.Classifier(false){};
    var pos: usize = 0;
    var result: Result = .{};
    while (pos < input.len) {
        const token = classifier.at(input, pos);
        result.checksum +%= @intFromEnum(token.record.line_break);
        result.count += 1;
        pos = token.end;
    }
    return result;
}

fn iterate(comptime consume_all: bool, bytes: []const u8) Result {
    var input = bytes;
    std.mem.doNotOptimizeAway(&input);
    var it = lb.iterator(input);
    var result: Result = .{};
    while (it.next()) |boundary| {
        if (consume_all or boundary.opportunity != .prohibited) result.add(boundary.offset, kind(boundary.opportunity));
    }
    return result;
}
fn full(bytes: []const u8) Result {
    return iterate(false, bytes);
}
fn allBoundaries(bytes: []const u8) Result {
    return iterate(true, bytes);
}

fn wrapPass(bytes: []const u8, comptime limit: usize) Result {
    var input = bytes;
    std.mem.doNotOptimizeAway(&input);
    var it = (zunic.text(input).wrap(.{ .max_columns = 80, .overflow = .grapheme }) catch unreachable).iterator();
    var result: Result = .{};
    while (result.count < limit) {
        const line = it.next() orelse break;
        result.add(line.start.value, line.end.value);
        result.checksum = result.checksum *% 31 +% line.columns.value;
    }
    return result;
}
fn wrapFull(bytes: []const u8) Result {
    return wrapPass(bytes, std.math.maxInt(usize));
}
fn wrapViewport(bytes: []const u8) Result {
    return wrapPass(bytes, 24);
}

// Separate diagnostic: predecoded tokens, not an end-to-end Rust comparison.
fn transitions(bytes: []const u8) Result {
    var input = bytes;
    std.mem.doNotOptimizeAway(&input);
    var result: Result = .{};
    if (token_count == 0) {
        result.add(input.len, 2);
        return result;
    }
    const first = tokens[0];
    var state = lb.State.firstWithRecord(first.record.line_break, first.codepoint orelse 0, first.record);
    var classifier = scalar.Classifier(false){};
    const eot = classifier.at(input, input.len);
    for (1..token_count) |i| {
        const token = tokens[i];
        const next = if (i + 1 < token_count) tokens[i + 1] else eot;
        const cp = token.codepoint orelse 0;
        const op = state.opportunityForRecord(input, cp, token.record, next.record.line_break, next.record, i + 1 < token_count, next.end, &classifier);
        state.consumeRecord(cp, token.record);
        if (op != .prohibited) result.add(token.start, kind(op));
    }
    result.add(input.len, 2);
    return result;
}

fn measure(io: std.Io, out: *std.Io.Writer, name: []const u8, op: []const u8, bytes: []const u8, comptime pass: fn ([]const u8) Result) !void {
    var iterations: usize = 1;
    while (true) {
        const start = std.Io.Clock.Timestamp.now(io, .awake);
        for (0..iterations) |_| std.mem.doNotOptimizeAway(pass(bytes));
        const elapsed = start.durationTo(std.Io.Clock.Timestamp.now(io, .awake)).raw.toNanoseconds();
        if (elapsed >= 50_000_000) break;
        iterations *= 2;
    }
    var samples: [15]u64 = undefined;
    var result: Result = .{};
    for (&samples) |*sample| {
        const start = std.Io.Clock.Timestamp.now(io, .awake);
        for (0..iterations) |_| {
            result = pass(bytes);
            std.mem.doNotOptimizeAway(result);
        }
        sample.* = @intCast(@divTrunc(start.durationTo(std.Io.Clock.Timestamp.now(io, .awake)).raw.toNanoseconds(), iterations));
    }
    try out.print("case={s} op={s} raw_samples={any}\n", .{ name, op, samples });
    std.mem.sort(u64, &samples, {}, std.sort.asc(u64));
    const median = samples[7];
    var devs: [15]u64 = undefined;
    for (samples, &devs) |s, *d| d.* = if (s > median) s - median else median - s;
    std.mem.sort(u64, &devs, {}, std.sort.asc(u64));
    try out.print("case={s} op={s} bytes={d} units={d} iterations={d} ns={d} mad={d} checksum={d}\n", .{
        name, op, bytes.len, result.count, iterations, median, devs[7], result.checksum,
    });
    try out.flush();
}

fn printStreams(out: *std.Io.Writer) !void {
    inline for (cases) |case| {
        try out.print("case={s} input=", .{case[0]});
        for (case[1]) |byte| try out.print("{x:0>2}", .{byte});
        try out.writeAll("\n");
        try out.print("case={s} stream=", .{case[0]});
        var it = lb.iterator(case[1]);
        while (it.next()) |boundary| {
            if (boundary.opportunity != .prohibited)
                try out.print("{d}:{s},", .{ boundary.offset, @tagName(boundary.opportunity) });
        }
        try out.writeAll("\n");
    }
    try out.flush();
}

pub fn main(init: std.process.Init) !void {
    var buf: [4096]u8 = undefined;
    var file = std.Io.File.stdout().writer(init.io, &buf);
    const out = &file.interface;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len == 1 or (args.len == 2 and (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h")))) {
        try out.writeAll(
            \\Usage: line-break-diagnostic MODE
            \\
            \\Modes:
            \\  --bench  Run timing benchmarks
            \\  --dump   Print exact output records (bytes are hex-encoded)
            \\  --streams  Alias for --dump
            \\  --help, -h  Print this help
            \\
            \\No arguments prints help. Corpora are embedded at build time.
            \\
        );
        return out.flush();
    }
    if (args.len == 2 and (std.mem.eql(u8, args[1], "--dump") or std.mem.eql(u8, args[1], "--streams"))) return printStreams(out);
    if (args.len != 2 or !std.mem.eql(u8, args[1], "--bench")) return error.UnexpectedArgument;
    try out.writeAll("protocol=1 suite=linebreak peer=zunic engine=zunic-machine unicode=16.0.0 samples=15 calibration_ms=50 input=bytes consumption=offset_status_checksum_v1\n");
    inline for (cases) |case| {
        const bytes = case[1];
        var classifier = scalar.Classifier(false){};
        var pos: usize = 0;
        token_count = 0;
        while (pos < bytes.len) {
            const token = classifier.at(bytes, pos);
            tokens[token_count] = token;
            token_count += 1;
            pos = token.end;
        }
        if (!std.meta.eql(transitions(bytes), full(bytes))) return error.TransitionMismatch;
        try measure(init.io, out, case[0], "all_boundaries", bytes, allBoundaries);
        try measure(init.io, out, case[0], "opportunities_only", bytes, full);
        try measure(init.io, out, case[0], "decode_classify", bytes, classify);
        try measure(init.io, out, case[0], "preclassified_rules", bytes, transitions);
        try measure(init.io, out, case[0], "wrap_full", bytes, wrapFull);
        try measure(init.io, out, case[0], "wrap_24", bytes, wrapViewport);
    }
}
