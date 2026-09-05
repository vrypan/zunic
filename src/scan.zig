//! Internal scanning helpers shared by wrapping accelerators.
//!
//! `Scanner` fuses UAX #29 cluster segmentation, cluster width measurement,
//! and the UAX #14 boundary decision at each cluster end into one pass that
//! decodes every scalar exactly once.
//!
//! Work bound: each scalar is decoded and classified once, held in a buffer
//! of at most two tokens, and consumed exactly once by both transition
//! machines; the scanner never rewinds. The only exception is LB25's second
//! following scalar, which `line_break.State.opportunityBefore` re-decodes on
//! demand at PO/PR before OP boundaries — at most one extra decode per
//! cluster end. Total decodes are therefore below twice the scalar count,
//! independent of wrapping width and line count. The bound is enforced by
//! instrumented-scanner counters in tests; instrumentation is a comptime
//! option and compiles to nothing in production builds.
const scalar = @import("scalar.zig");
const grapheme = @import("grapheme.zig");
const line_break = @import("line_break.zig");

pub const ascii = @import("ascii_scan.zig");

/// One extended grapheme cluster, its terminal width (`3` is the replacement
/// sentinel, as in `grapheme.Span`), whether it is a hard line terminator,
/// and whether UAX #14 permits a break immediately after it.
pub const Cluster = struct {
    start: usize,
    end: usize,
    columns: u3,
    hard: bool,
    can_break: bool,
};

pub const Counters = struct {
    decoded_scalars: usize = 0,
    max_buffered: usize = 0,
};

pub fn Scanner(comptime instrumented: bool) type {
    return struct {
        bytes: []const u8,
        decode_pos: usize = 0,
        buf0: ?scalar.Token = null,
        buf1: ?scalar.Token = null,
        lb: line_break.State = .{},
        lb_started: bool = false,
        counters: if (instrumented) Counters else void = if (instrumented) .{} else {},

        const Self = @This();

        pub fn next(self: *Self) ?Cluster {
            const first = self.take() orelse return null;
            const first_cp = first.codepoint orelse 0;
            if (self.lb_started) {
                const current = self.lb.resolveCurrent(first.line_break, first_cp);
                self.lb.consume(first.line_break, current, first_cp);
            } else {
                self.lb = line_break.State.first(first.line_break, first_cp);
                self.lb_started = true;
            }
            const start = first.start;
            const hard = line_break.isHardClass(first.line_break);
            var state = grapheme.ClusterState.init(grapheme.classify(first));
            var measure = grapheme.ClusterMeasure{};
            measure.add(first);
            var end = first.end;

            while (true) {
                const lookahead = self.peek0() orelse
                    return .{ .start = start, .end = end, .columns = measure.finish(), .hard = hard, .can_break = true };
                const classification = grapheme.classify(lookahead);
                const cp = lookahead.codepoint orelse 0;
                const current = self.lb.resolveCurrent(lookahead.line_break, cp);
                if (state.breakBeforeNext(classification)) {
                    // The cluster ends before `lookahead`, which stays
                    // buffered as the next cluster's first scalar; its
                    // line-break consumption happens there, after the
                    // boundary in front of it has been decided here.
                    const opportunity = if (self.peek1()) |following|
                        self.lb.opportunityBefore(self.bytes, lookahead.line_break, current, cp, following.line_break, following.codepoint orelse 0, true, following.end)
                    else
                        self.lb.opportunityBefore(self.bytes, lookahead.line_break, current, cp, .al, 0, false, lookahead.end);
                    return .{ .start = start, .end = end, .columns = measure.finish(), .hard = hard, .can_break = opportunity != .prohibited };
                }
                self.buf0 = self.buf1;
                self.buf1 = null;
                self.lb.consume(lookahead.line_break, current, cp);
                state.consume(classification);
                measure.add(lookahead);
                end = lookahead.end;
            }
        }

        fn decode(self: *Self) scalar.Token {
            if (instrumented) self.counters.decoded_scalars += 1;
            const token = scalar.at(self.bytes, self.decode_pos);
            self.decode_pos = token.end;
            return token;
        }

        fn take(self: *Self) ?scalar.Token {
            if (self.buf0) |token| {
                self.buf0 = self.buf1;
                self.buf1 = null;
                return token;
            }
            if (self.decode_pos >= self.bytes.len) return null;
            return self.decode();
        }

        fn peek0(self: *Self) ?scalar.Token {
            if (self.buf0 == null) {
                if (self.decode_pos >= self.bytes.len) return null;
                self.buf0 = self.decode();
                if (instrumented) self.counters.max_buffered = @max(self.counters.max_buffered, self.buffered());
            }
            return self.buf0;
        }

        fn peek1(self: *Self) ?scalar.Token {
            if (self.buf1 == null) {
                if (self.decode_pos >= self.bytes.len) return null;
                self.buf1 = self.decode();
                if (instrumented) self.counters.max_buffered = @max(self.counters.max_buffered, self.buffered());
            }
            return self.buf1;
        }

        fn buffered(self: *const Self) usize {
            var count: usize = 0;
            if (self.buf0 != null) count += 1;
            if (self.buf1 != null) count += 1;
            return count;
        }
    };
}
