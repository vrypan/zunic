//! Iterator/state protocol consistency, including prohibited/mandatory events.
//! Both use the machine; this is not an independent Unicode correctness oracle.
const std = @import("std");
const internal = @import("internal");
const lb = internal.line_break;
const decoded_token = internal.decoded_token;

fn verify(bytes: []const u8) !usize {
    var actual = lb.iterator(bytes);
    var classifier = decoded_token.Classifier(false){};
    var offset: usize = 0;
    var state: ?lb.State = null;
    var count: usize = 0;
    while (offset < bytes.len) {
        const token = classifier.at(bytes, offset);
        const next = classifier.at(bytes, token.end);
        const cp = token.codepoint orelse 0;
        const expected: lb.Opportunity = if (state) |*s|
            s.opportunityForRecord(bytes, cp, token.record, next.record.line_break, next.record, token.end < bytes.len, next.end, &classifier)
        else
            .prohibited;
        const boundary = actual.next() orelse return error.MissingBoundary;
        if (boundary.offset != offset or boundary.opportunity != expected) {
            std.debug.print("mismatch offset={d} expected={t} actual={any}\n", .{ offset, expected, boundary });
            return error.BoundaryMismatch;
        }
        if (state) |*s| s.consumeRecord(cp, token.record) else {
            state = lb.State.firstWithRecord(token.record.line_break, cp, token.record);
        }
        offset = token.end;
        count += 1;
    }
    const eot = actual.next() orelse return error.MissingEot;
    if (eot.offset != bytes.len or eot.opportunity != .mandatory) return error.InvalidEot;
    if (actual.next() != null or actual.next() != null) return error.RepeatedEot;
    return count + 1;
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len == 1 or (args.len == 2 and (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h")))) {
        var buffer: [1024]u8 = undefined;
        var file = std.Io.File.stdout().writer(init.io, &buffer);
        try file.interface.writeAll("Usage: verify-semantic --check\n\n  --check  Run untimed protocol checks\n  --help, -h  Print this help\n");
        return file.interface.flush();
    }
    if (args.len != 2 or !std.mem.eql(u8, args[1], "--check")) return error.UnexpectedArgument;

    // Known pre-015 limitation: LB1-resolved SA marks do not receive LB9
    // inheritance. This diagnostic records existing behavior, not UAX approval.
    _ = try verify("a\u{0e31}");
    var sa_probe = lb.iterator("a\u{0e31}");
    _ = sa_probe.next();
    const sa_boundary = sa_probe.next().?;
    std.debug.print("known SA-mark limitation: offset={d}, actual={t}, UAX LB1/LB9 expected=prohibited (known inherited defect)\n", .{ sa_boundary.offset, sa_boundary.opportunity });
    inline for (.{ "arabic", "english", "hindi", "japanese", "korean", "mandarin", "russian", "source_code" }) |name| {
        const bytes = @embedFile("texts/" ++ name ++ ".txt");
        const count = try verify(bytes);
        std.debug.print("{s}: {d} bytes, {d} protocol boundaries verified\n", .{ name, bytes.len, count });
    }
    for ([_][]const u8{ "", "\n\xe2\x81\xa0", "\r\n", "\x00\xf0\x91\x80\x83\xe2\x97\x8c", "\xff\xc0\x80\xf4\x90\x80\x80\xed\xa0\x80\xe2\x82" }) |bytes| _ = try verify(bytes);
}
