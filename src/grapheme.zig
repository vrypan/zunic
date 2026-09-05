//! Default extended-grapheme boundaries (UAX #29 core rules).
const scalar = @import("scalar.zig");
const properties = @import("properties.zig");

pub const Span = struct {
    start: usize,
    end: usize,
    /// Terminal width for this cluster; `3` is the replacement sentinel.
    columns: u3 = 0,
};

const Property = enum { other, cr, lf, control, extend, zwj, ri, prepend, spacing_mark, l, v, t, lv, lvt, ep };
const InCB = enum { none, consonant, extend, linker };
const Classification = struct { property: Property, incb: InCB };
const Token = struct { scalar: scalar.Token, classification: Classification };

pub const Iterator = struct {
    bytes: []const u8,
    pos: usize = 0,
    pending: ?Token = null,

    pub fn next(self: *Iterator) ?Span {
        if (self.pos >= self.bytes.len) return null;
        const start = self.pos;
        const first = self.takeToken();
        var measure = ClusterMeasure{};
        measure.add(first.scalar);
        const first_classification = first.classification;
        var previous = first_classification.property;
        var ri_count: usize = if (previous == .ri) 1 else 0;
        var ep_before_zwj = previous == .ep;
        var zwj_after_ep = false;
        var incb_linker_after_consonant = false;
        var incb_seen_consonant = first_classification.incb == .consonant;

        while (self.pos < self.bytes.len) {
            const lookahead = self.peekToken();
            const classification = lookahead.classification;
            const current = classification.property;
            const current_incb = classification.incb;
            if (breakBefore(previous, current, ri_count, zwj_after_ep, incb_linker_after_consonant, current_incb)) break;

            _ = self.takeToken();
            measure.add(lookahead.scalar);
            if (current == .ri) ri_count += 1 else if (current != .extend) ri_count = 0;
            if (current == .zwj) {
                zwj_after_ep = ep_before_zwj;
            } else if (current == .ep) {
                ep_before_zwj = true;
                zwj_after_ep = false;
            } else if (current != .extend) {
                ep_before_zwj = false;
                zwj_after_ep = false;
            }
            switch (current_incb) {
                .consonant => {
                    incb_seen_consonant = true;
                    incb_linker_after_consonant = false;
                },
                .linker => {
                    if (incb_seen_consonant) incb_linker_after_consonant = true;
                },
                .extend => {},
                .none => {
                    incb_seen_consonant = false;
                    incb_linker_after_consonant = false;
                },
            }
            previous = current;
        }
        return .{ .start = start, .end = self.pos, .columns = measure.finish() };
    }

    fn takeToken(self: *Iterator) Token {
        const token = self.pending orelse self.decodeAt(self.pos);
        self.pending = null;
        self.pos = token.scalar.end;
        return token;
    }

    fn peekToken(self: *Iterator) Token {
        if (self.pending == null) self.pending = self.decodeAt(self.pos);
        return self.pending.?;
    }

    fn decodeAt(self: *const Iterator, offset: usize) Token {
        const token = scalar.at(self.bytes, offset);
        return .{ .scalar = token, .classification = classify(token) };
    }
};

const ClusterMeasure = struct {
    columns: usize = 0,
    has_base: bool = false,
    has_pictograph: bool = false,
    has_ri: bool = false,

    fn add(self: *ClusterMeasure, token: scalar.Token) void {
        const cp = token.codepoint orelse return;
        if (cp < 0x20 or cp == 0x7f) return;
        if (token.cell_width != 0) {
            self.has_base = true;
            self.columns += token.cell_width;
        }
        if (token.grapheme.extended_pictographic) self.has_pictograph = true;
        if (cp >= 0x1f1e6 and cp <= 0x1f1ff) self.has_ri = true;
    }

    fn finish(self: ClusterMeasure) u3 {
        if (!self.has_base) return 0;
        if (self.has_pictograph or self.has_ri) return 2;
        if (self.columns > 2) return 3;
        return @intCast(self.columns);
    }
};

pub fn iterator(bytes: []const u8) Iterator {
    return .{ .bytes = bytes };
}

fn breakBefore(previous: Property, current: Property, ri_count: usize, zwj_after_ep: bool, incb_linker_after_consonant: bool, current_incb: InCB) bool {
    if (previous == .cr and current == .lf) return false;
    if (isControl(previous) or isControl(current)) return true;
    if (previous == .l and (current == .l or current == .v or current == .lv or current == .lvt)) return false;
    if ((previous == .lv or previous == .v) and (current == .v or current == .t)) return false;
    if ((previous == .lvt or previous == .t) and current == .t) return false;
    if (current == .extend or current == .zwj or current == .spacing_mark) return false;
    if (previous == .prepend) return false;
    if (previous == .zwj and current == .ep and zwj_after_ep) return false;
    if (incb_linker_after_consonant and current_incb == .consonant) return false;
    if (previous == .ri and current == .ri and ri_count % 2 == 1) return false;
    return true;
}

fn isControl(p: Property) bool {
    return p == .cr or p == .lf or p == .control;
}

fn classify(token: scalar.Token) Classification {
    const property: Property = switch (token.grapheme.gcb) {
        .other => if (token.grapheme.extended_pictographic) .ep else .other,
        .regional_indicator => .ri,
        .spacingmark => .spacing_mark,
        else => @enumFromInt(@intFromEnum(token.grapheme.gcb)),
    };
    return .{
        .property = property,
        .incb = @enumFromInt(@intFromEnum(token.grapheme.incb)),
    };
}

pub fn isExtendedPictographic(cp: u21) bool {
    return properties.graphemeProperties(cp).extended_pictographic;
}
