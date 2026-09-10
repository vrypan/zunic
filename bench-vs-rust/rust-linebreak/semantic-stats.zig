//! Untimed action/decoder counters; never linked into the measured loops.
const std = @import("std");
const internal = @import("internal");
const lb = internal.line_break;
const scalar = internal.scalar;
const data = internal.transitions;

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len == 1 or (args.len == 2 and (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h")))) {
        var buffer: [1024]u8 = undefined;
        var file = std.Io.File.stdout().writer(init.io, &buffer);
        try file.interface.writeAll("Usage: semantic-stats --stats\n\n  --stats  Run untimed diagnostic counters\n  --help, -h  Print this help\n");
        return file.interface.flush();
    }
    if (args.len != 2 or !std.mem.eql(u8, args[1], "--stats")) return error.UnexpectedArgument;

    std.debug.print("state_bytes={d} transition_data_bytes={d}\n", .{ @sizeOf(lb.State), data.data_bytes });
    inline for (.{ "arabic", "english", "hindi", "japanese", "korean", "mandarin", "russian", "source_code" }) |name| {
        const bytes = @embedFile("texts/" ++ name ++ ".txt");
        var classifier = scalar.Classifier(true){};
        const first = classifier.at(bytes, 0);
        var state = lb.State.firstWithRecord(first.record.line_break, first.codepoint orelse 0, first.record);
        var token = classifier.at(bytes, first.end);
        var counts = [_]usize{0} ** 8;
        var scalars: usize = 1;
        while (token.start < bytes.len) {
            const next = classifier.at(bytes, token.end);
            const cp = token.codepoint orelse 0;
            const r = token.record;
            const entry = data.transitions[@as(usize, state.id) * data.category_count + r.line_break_category];
            counts[entry >> 8] += 1;
            std.mem.doNotOptimizeAway(state.opportunityForRecord(bytes, cp, r, next.record.line_break, next.record, token.end < bytes.len, next.end, &classifier));
            state.consumeRecord(cp, r);
            if (state.id != @as(u8, @truncate(entry))) return error.ReportingKeyMismatch;
            scalars += 1;
            token = next;
        }
        std.debug.print("case={s} scalars={d} actions={any} extra_lookahead_decodes={d} property_lookups={d}\n", .{ name, scalars, counts, classifier.decoded_scalars - scalars, classifier.property_lookups });
    }
}
