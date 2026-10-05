//! Default extended-grapheme boundaries (UAX #29 core rules).
const std = @import("std");
const decoded_token = @import("encoding").decoded_token;
const boundary = @import("grapheme_machine.zig");

// Preserve the engine interface for streaming, layout, and reference tests.
pub const Classification = boundary.Classification;
pub const ClusterState = boundary.ClusterState;
pub const machine = boundary.machine;
pub const TableState = boundary.TableState;
pub const categoryOf = boundary.categoryOf;
pub const categoryForCodepoint = boundary.categoryForCodepoint;
pub const classify = boundary.classify;
pub const PresentationMeasure = @import("presentation.zig").Measure;

pub const Span = struct {
    start: usize,
    end: usize,
    /// Terminal width for this cluster, as `ClusterMeasure.finish` encodes it:
    /// `0` no base, `1`/`2` renderable column counts, `3` the replacement
    /// sentinel. Decode it with `displayColumns` rather than by hand.
    columns: u3 = 0,
};

/// The column count a `Span.columns` (or `scan.Cluster.columns`) value
/// occupies on screen: the sentinel renders as one replacement column, and
/// every other value already is its own width.
///
/// This is the only place that knows what `3` means. Consumers that open-code
/// the comparison drift from `ClusterMeasure.finish` the moment the encoding
/// changes, which is why measurement, wrapping and the text view all route
/// through here.
pub inline fn displayColumns(columns: u3) usize {
    return if (columns == replacement_sentinel) 1 else columns;
}

/// Whether a `Span.columns` value describes something the terminal can show.
/// Only the two real column counts qualify: `0` has no base to draw, and the
/// sentinel stands in for a cluster too wide to render as itself.
pub inline fn isRenderable(columns: u3) bool {
    return columns == 1 or columns == 2;
}

/// `finish` reports "wider than two columns" as this value, which the width
/// policy renders as a single replacement column.
pub const replacement_sentinel: u3 = 3;

const Token = struct { scalar: decoded_token.Token, category: u8 };

pub const Iterator = struct {
    bytes: []const u8,
    pos: usize = 0,
    pending: ?Token = null,

    // Table-driven: one read per scalar yields the boundary decision and the
    // successor state, replacing `classify`'s switch plus `breakBefore`'s
    // comparison chain and `consume`'s field updates.
    pub inline fn next(self: *Iterator) ?Span {
        return self.nextSpan(true);
    }

    /// Unmeasured callers exclude measurement explicitly: the cold rescan
    /// must not depend on the optimizer removing an unused column count.
    pub inline fn nextSpan(self: *Iterator, comptime measured: bool) ?Span {
        if (self.pos >= self.bytes.len) return null;
        const start = self.pos;
        const first = self.takeToken();
        var measure = ClusterMeasure{};
        if (measured) measure.add(first.scalar);
        var state = TableState.init(first.category);

        while (self.pos < self.bytes.len) {
            const lookahead = self.peekToken();
            if (state.step(lookahead.category)) break;
            _ = self.takeToken();
            if (measured) measure.add(lookahead.scalar);
        }
        return .{ .start = start, .end = self.pos, .columns = if (measured) measure.finish(self.bytes[start..self.pos]) else 0 };
    }

    // These helpers complete the inline chain from decoded_token.at to the public
    // iterator. Inlining only the decoder can move an out-of-line call here,
    // retaining token materialization and preventing caller specialization.
    inline fn takeToken(self: *Iterator) Token {
        const token = self.pending orelse self.decodeAt(self.pos);
        self.pending = null;
        self.pos = token.scalar.end;
        return token;
    }

    inline fn peekToken(self: *Iterator) Token {
        if (self.pending == null) self.pending = self.decodeAt(self.pos);
        return self.pending.?;
    }

    inline fn decodeAt(self: *const Iterator, offset: usize) Token {
        const token = decoded_token.at(self.bytes, offset);
        return .{ .scalar = token, .category = categoryOf(token) };
    }
};

pub const ClusterMeasure = struct {
    columns: usize = 0,
    has_base: bool = false,
    needs_presentation: bool = false,
    has_ri: bool = false,

    /// Regional indicators are exactly `gcb == .regional_indicator`, checked
    /// over all 1,114,112 code points with zero mismatches, so that range
    /// compare is a property bit. The C0/DEL skip cannot be widened to the GCB
    /// control class: 3804 code points share that class with width 1, C1
    /// controls among them, and they must keep their column.
    pub fn add(self: *ClusterMeasure, token: decoded_token.Token) void {
        const cp = token.codepoint orelse return;
        if (cp < 0x20 or cp == 0x7f) return;
        if (token.cell_width != 0) {
            self.has_base = true;
            self.columns += token.cell_width;
        }
        // Selectors also cover non-pictographic variation bases (#, *, digits).
        // No previous-scalar or selector state lives across this scan loop.
        if (token.presentation_candidate) self.needs_presentation = true;
        if (token.grapheme.gcb == .regional_indicator) self.has_ri = true;
    }

    pub inline fn finish(self: ClusterMeasure, bytes: []const u8) u3 {
        if (!self.has_base) return 0;
        if (self.needs_presentation or self.has_ri) return exceptionalWidth(bytes, self.columns, self.has_ri);
        if (self.columns > 2) return replacement_sentinel;
        return @intCast(self.columns);
    }
};

noinline fn exceptionalWidth(bytes: []const u8, columns: usize, has_ri: bool) u3 {
    if (has_ri) return 2;
    if (mayHaveSelector(bytes)) return presentationWidth(bytes);
    return @intCast(@min(columns, 2));
}

/// Both selectors begin with EF. False positives only cause an unnecessary
/// rescan; no valid selector can be missed. This byte probe runs exclusively
/// on exceptional clusters, outside the ordinary measurement loop.
pub fn mayHaveSelector(bytes: []const u8) bool {
    return std.mem.indexOfScalar(u8, bytes, 0xef) != null;
}

/// Remeasure an exceptional cluster once, with selector state confined to
/// this call. Reader uses the same accumulator incrementally without replay.
pub noinline fn presentationWidth(bytes: []const u8) u3 {
    return presentationWidthImpl(false, bytes, undefined);
}

pub const PresentationCounters = struct {
    decoded_scalars: usize = 0,
    property_lookups: usize = 0,
};

pub noinline fn presentationWidthCounted(bytes: []const u8, counters: *PresentationCounters) u3 {
    return presentationWidthImpl(true, bytes, counters);
}

fn presentationWidthImpl(comptime instrumented: bool, bytes: []const u8, counters: *PresentationCounters) u3 {
    var measure: PresentationMeasure = .{};
    var tokens = decoded_token.iterator(bytes);
    while (tokens.next()) |token| {
        if (instrumented) {
            counters.decoded_scalars += 1;
            if (token.codepoint) |cp| {
                counters.property_lookups += 1;
                if ((cp == 0xfe0e or cp == 0xfe0f) and measure.previous != null) counters.property_lookups += 1;
            }
        }
        measure.addBounded(token);
    }
    return measure.finish();
}

pub fn iterator(bytes: []const u8) Iterator {
    return .{ .bytes = bytes };
}
