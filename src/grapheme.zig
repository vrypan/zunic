//! Default extended-grapheme boundaries (UAX #29 core rules).
const utf8 = @import("utf8.zig");
const properties = @import("properties.zig");

pub const Span = struct { start: usize, end: usize };

const Property = enum { other, cr, lf, control, extend, zwj, ri, prepend, spacing_mark, l, v, t, lv, lvt, ep };
const InCB = enum { none, consonant, extend, linker };

pub const Iterator = struct {
    bytes: []const u8,
    pos: usize = 0,

    pub fn next(self: *Iterator) ?Span {
        if (self.pos >= self.bytes.len) return null;
        const start = self.pos;
        const first = utf8.step(self.bytes[self.pos..]);
        self.pos += first.len;
        var previous = property(first.cp);
        var ri_count: usize = if (previous == .ri) 1 else 0;
        var ep_before_zwj = previous == .ep;
        var zwj_after_ep = false;
        var incb_linker_after_consonant = false;
        var incb_seen_consonant = indicConjunct(first.cp) == .consonant;

        while (self.pos < self.bytes.len) {
            const next_step = utf8.step(self.bytes[self.pos..]);
            const current = property(next_step.cp);
            const current_incb = indicConjunct(next_step.cp);
            if (breakBefore(previous, current, ri_count, zwj_after_ep, incb_linker_after_consonant, current_incb)) break;

            self.pos += next_step.len;
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
        return .{ .start = start, .end = self.pos };
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

fn property(maybe_cp: ?u21) Property {
    const cp = maybe_cp orelse return .other;
    if (inRanges(&properties.gcb_cr, cp)) return .cr;
    if (inRanges(&properties.gcb_lf, cp)) return .lf;
    if (inRanges(&properties.gcb_control, cp)) return .control;
    if (inRanges(&properties.gcb_l, cp)) return .l;
    if (inRanges(&properties.gcb_v, cp)) return .v;
    if (inRanges(&properties.gcb_t, cp)) return .t;
    if (inRanges(&properties.gcb_lv, cp)) return .lv;
    if (inRanges(&properties.gcb_lvt, cp)) return .lvt;
    if (inRanges(&properties.gcb_prepend, cp)) return .prepend;
    if (inRanges(&properties.gcb_spacingmark, cp)) return .spacing_mark;
    if (inRanges(&properties.gcb_extend, cp)) return .extend;
    if (inRanges(&properties.gcb_zwj, cp)) return .zwj;
    if (inRanges(&properties.gcb_regional_indicator, cp)) return .ri;
    if (isExtendedPictographic(cp)) return .ep;
    return .other;
}

pub fn isExtendedPictographic(cp: u21) bool {
    return inRanges(&properties.emoji_extended_pictographic, cp);
}

fn indicConjunct(maybe_cp: ?u21) InCB {
    const cp = maybe_cp orelse return .none;
    if (inRanges(&properties.incb_incb__consonant, cp)) return .consonant;
    if (inRanges(&properties.incb_incb__extend, cp)) return .extend;
    if (inRanges(&properties.incb_incb__linker, cp)) return .linker;
    return .none;
}

fn inRanges(ranges: []const properties.Range, cp: u21) bool {
    var lo: usize = 0;
    var hi: usize = ranges.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const r = ranges[mid];
        if (cp < r.lo) hi = mid else if (cp > r.hi) lo = mid + 1 else return true;
    }
    return false;
}
