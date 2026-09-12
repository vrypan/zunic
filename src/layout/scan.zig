//! Internal scanning helpers shared by wrapping accelerators.
//!
//! `Scanner` fuses UAX #29 cluster segmentation, cluster width measurement,
//! and the UAX #14 boundary decision at each cluster end into one pass that
//! decodes every scalar exactly once.
//!
//! Work bound: each scalar is decoded and classified once, held in a buffer
//! of at most two tokens, and consumed exactly once by both transition
//! machines; the scanner never rewinds. The only exception is LB25's second
//! following scalar, which `line_break.State.opportunityForRecord` re-decodes on
//! demand at PO/PR before OP boundaries — at most one extra decode per
//! cluster end. These lookahead decodes use the same counted classifier.
//! Every valid decode loads one property record; rule predicates reuse its
//! bits, including those of previous base scalars retained by the state.
//! Total decodes are therefore below twice the scalar count,
//! independent of wrapping width and line count. The bound is enforced by
//! instrumented-scanner counters in tests; instrumentation is a comptime
//! option and compiles to nothing in production builds.
const std = @import("std");
const decoded_token = @import("encoding").decoded_token;
const grapheme = @import("segmentation").grapheme;
const line_break = @import("linebreak");
const properties = @import("tables").properties;

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
    property_lookups: usize = 0,
    max_buffered: usize = 0,
    /// Line-break transition entries read. One per consumed scalar is the
    /// floor; a boundary that queried and then re-consumed the same
    /// `(state, category)` pair would show one extra per cluster.
    transition_reads: usize = 0,
};

pub fn Scanner(comptime instrumented: bool) type {
    return struct {
        bytes: []const u8,
        decode_pos: usize = 0,
        buf0: ?decoded_token.ClassifiedToken = null,
        buf1: ?decoded_token.ClassifiedToken = null,
        classifier: decoded_token.Classifier(instrumented) = .{},
        lb: line_break.State = .{},
        /// The boundary step consumes the lookahead's line-break category with
        /// the same table entry that supplied its opcode. This records that the
        /// next `next()` must not consume that scalar a second time.
        lb_consumed: bool = false,
        counters: if (instrumented) Counters else void = if (instrumented) .{} else {},

        const Self = @This();

        pub inline fn next(self: *Self) ?Cluster {
            const first_decoded = self.take() orelse return null;
            const first = first_decoded.scalarToken();
            if (self.lb_consumed) self.lb_consumed = false else self.consumeLineBreak(first_decoded.record.line_break_category);
            const start = first.start;
            const hard = line_break.isHardClass(first.line_break);
            var state = grapheme.TableState.init(grapheme.categoryOf(first));
            var measure = grapheme.ClusterMeasure{};
            measure.add(first);
            var end = first.end;

            while (true) {
                const decoded = self.peek0() orelse
                    return .{ .start = start, .end = end, .columns = measure.finish(), .hard = hard, .can_break = true };
                const lookahead = decoded.scalarToken();
                const category = grapheme.categoryOf(lookahead);
                if (state.step(category)) {
                    // The cluster ends before `lookahead`, which stays
                    // buffered as the next cluster's first scalar; its
                    // line-break consumption happens there, after the
                    // boundary in front of it has been decided here.
                    // One entry serves both the boundary decision and the
                    // consumption the next call would otherwise repeat.
                    // `opportunityForCategory` was a pure query over the same
                    // `(state, category)` pair that the next call consumed, so
                    // advancing here is observationally identical.
                    const opcode = self.consumeLineBreakAndOpcode(decoded.record.line_break_category);
                    self.lb_consumed = true;
                    // Decode the scalar after the lookahead unconditionally,
                    // even though only opcodes 3-7 read it. This is never
                    // wasted: the token stays in `buf1` and becomes the next
                    // cluster's first scalar. Issuing it a cluster early hides
                    // the latency of its property-table lookup, which is worth
                    // 4-7% on real documents (japanese, mandarin, english,
                    // source_code). Deferring it to the contextual arm, as
                    // `line_break.Iterator` does, looks like less work and
                    // measures slower; see private/benchmarks/017-*.md.
                    const opportunity = if (self.peek1()) |following|
                        line_break.State.opportunityForOpcode(opcode, self.bytes, following.record.line_break, following.record, true, following.end, &self.classifier)
                    else
                        line_break.State.opportunityForOpcode(opcode, self.bytes, .al, comptime properties.record(0), false, lookahead.end, &self.classifier);
                    self.updateCounters();
                    return .{ .start = start, .end = end, .columns = measure.finish(), .hard = hard, .can_break = opportunity != .prohibited };
                }
                self.buf0 = self.buf1;
                self.buf1 = null;
                self.consumeLineBreak(decoded.record.line_break_category);
                // `step` already advanced the state on the non-breaking path.
                measure.add(lookahead);
                end = lookahead.end;
            }
        }

        inline fn consumeLineBreak(self: *Self, category: u8) void {
            if (instrumented) self.counters.transition_reads += 1;
            self.lb.consumeCategory(category);
        }

        inline fn consumeLineBreakAndOpcode(self: *Self, category: u8) u8 {
            if (instrumented) self.counters.transition_reads += 1;
            return self.lb.consumeCategoryAndOpcode(category);
        }

        fn decode(self: *Self) decoded_token.ClassifiedToken {
            const token = self.classifier.at(self.bytes, self.decode_pos);
            self.updateCounters();
            self.decode_pos = token.end;
            return token;
        }

        fn updateCounters(self: *Self) void {
            if (instrumented) {
                self.counters.decoded_scalars = self.classifier.decoded_scalars;
                self.counters.property_lookups = self.classifier.property_lookups;
            }
        }

        fn take(self: *Self) ?decoded_token.ClassifiedToken {
            if (self.buf0) |token| {
                self.buf0 = self.buf1;
                self.buf1 = null;
                return token;
            }
            if (self.decode_pos >= self.bytes.len) return null;
            return self.decode();
        }

        fn peek0(self: *Self) ?decoded_token.ClassifiedToken {
            if (self.buf0 == null) {
                if (self.decode_pos >= self.bytes.len) return null;
                self.buf0 = self.decode();
                if (instrumented) self.counters.max_buffered = @max(self.counters.max_buffered, self.buffered());
            }
            return self.buf0;
        }

        /// The scalar after `peek0`'s. Only meaningful once `buf0` holds the
        /// first one: called on an empty buffer it would decode the *first*
        /// scalar into `buf1`, and `take` would then hand them back out of
        /// order. The single caller peeks in order; the assert keeps a second
        /// one honest.
        fn peek1(self: *Self) ?decoded_token.ClassifiedToken {
            std.debug.assert(self.buf0 != null);
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
