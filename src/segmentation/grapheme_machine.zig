//! UAX #29 reference rules and compile-time boundary transition tables.
const decoded_token = @import("encoding").decoded_token;
const grapheme_properties = @import("tables").grapheme;

const Property = enum { other, cr, lf, control, extend, zwj, ri, prepend, spacing_mark, l, v, t, lv, lvt, ep };
const InCB = enum { none, consonant, extend, linker };
pub const Classification = struct { property: Property, incb: InCB };

/// The reference UAX #29 transition. Since plan 019 this is no longer on the
/// hot path: `machine` evaluates it at comptime for every reachable
/// `(state, category)` pair and the runtime reads the resulting table. It
/// remains the single definition of the rules, and the differential test in
/// `scan_test.zig` checks the table against it over real byte streams.
pub const ClusterState = struct {
    previous: Property,
    ri_count: usize,
    ep_before_zwj: bool,
    zwj_after_ep: bool = false,
    incb_linker_after_consonant: bool = false,
    incb_seen_consonant: bool,

    pub inline fn init(classification: Classification) ClusterState {
        return .{
            .previous = classification.property,
            .ri_count = if (classification.property == .ri) 1 else 0,
            .ep_before_zwj = classification.property == .ep,
            .incb_seen_consonant = classification.incb == .consonant,
        };
    }

    pub inline fn breakBeforeNext(self: ClusterState, classification: Classification) bool {
        return breakBefore(self.previous, classification.property, self.ri_count, self.zwj_after_ep, self.incb_linker_after_consonant, classification.incb);
    }

    pub inline fn consume(self: *ClusterState, classification: Classification) void {
        const current = classification.property;
        if (current == .ri) self.ri_count += 1 else if (current != .extend) self.ri_count = 0;
        if (current == .zwj) {
            self.zwj_after_ep = self.ep_before_zwj;
            // GB11 permits Extend* before one ZWJ, not a chain of ZWJs.
            self.ep_before_zwj = false;
        } else if (current == .ep) {
            self.ep_before_zwj = true;
            self.zwj_after_ep = false;
        } else if (current != .extend) {
            self.ep_before_zwj = false;
            self.zwj_after_ep = false;
        }
        switch (classification.incb) {
            .consonant => {
                self.incb_seen_consonant = true;
                self.incb_linker_after_consonant = false;
            },
            .linker => {
                if (self.incb_seen_consonant) self.incb_linker_after_consonant = true;
            },
            .extend => {},
            .none => {
                self.incb_seen_consonant = false;
                self.incb_linker_after_consonant = false;
            },
        }
        self.previous = current;
    }
};

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

/// Production transition table built at comptime from the reference rules
/// above, so the runtime and reference transitions agree by construction.
///
/// State packs the six observable fields of the reference `ClusterState` into
/// nine bits; `ri_count` contributes only its parity, which is all
/// `breakBefore` reads. The category is a dense id for the distinct
/// `(Property, InCB)` pairs reachable from a `GraphemeProperties` value, and
/// is looked up by the seven bits `decoded_token.at` has already unpacked.
pub const machine = struct {
    const State = packed struct(u9) {
        previous: u4,
        ri_parity: bool,
        ep_before_zwj: bool,
        zwj_after_ep: bool,
        incb_seen_consonant: bool,
        incb_linker_after_consonant: bool,
    };

    const state_count = 512;

    fn decode(id: u9) State {
        return @bitCast(id);
    }

    fn classificationOfKey(key: u7) ?Classification {
        const gcb_raw: u4 = @truncate(key);
        // GraphemeClass has 14 members; 14 and 15 never occur in a record.
        if (@as(u8, gcb_raw) >= @typeInfo(grapheme_properties.GraphemeClass).@"enum".field_names.len) return null;
        const g: grapheme_properties.GraphemeProperties = @bitCast(key);
        const property: Property = switch (g.gcb) {
            .other => if (g.extended_pictographic) .ep else .other,
            .regional_indicator => .ri,
            .spacingmark => .spacing_mark,
            else => @fromBackingInt(@intCast(@backingInt(g.gcb))),
        };
        return .{ .property = property, .incb = @fromBackingInt(@intCast(@backingInt(g.incb))) };
    }

    /// Property keys that actually occur in Unicode 17. Enumerating all 128
    /// encodable keys yields 60 categories; only a fraction are real.
    const occurring = blk: {
        @setEvalBranchQuota(2000000);
        var seen: [128]bool = @splat(false);
        for (grapheme_properties.record_data) |raw| seen[@as(u7, @truncate(raw))] = true;
        break :blk seen;
    };

    /// Distinct classifications over occurring keys, in first-seen order.
    const catalogue = blk: {
        @setEvalBranchQuota(200000);
        var list: [128]Classification = undefined;
        var len: usize = 0;
        for (0..128) |k| {
            if (!occurring[k]) continue;
            const c = classificationOfKey(@intCast(k)) orelse continue;
            var dup = false;
            for (list[0..len]) |e| {
                if (e.property == c.property and e.incb == c.incb) dup = true;
            }
            if (!dup) {
                list[len] = c;
                len += 1;
            }
        }
        break :blk .{ .items = list, .len = len };
    };

    pub const category_count = catalogue.len;

    /// Seven unpacked property bits -> dense category id. 128 bytes, L1 resident.
    pub const category_of = blk: {
        @setEvalBranchQuota(200000);
        var table: [128]u8 = @splat(0);
        for (0..128) |k| {
            const c = classificationOfKey(@intCast(k)) orelse continue;
            for (catalogue.items[0..catalogue.len], 0..) |e, i| {
                if (e.property == c.property and e.incb == c.incb) {
                    table[k] = @intCast(i);
                    break;
                }
            }
        }
        break :blk table;
    };

    fn reference(id: u9) ClusterState {
        const st = decode(id);
        return .{
            .previous = @fromBackingInt(@intCast(st.previous)),
            .ri_count = if (st.ri_parity) 1 else 0,
            .ep_before_zwj = st.ep_before_zwj,
            .zwj_after_ep = st.zwj_after_ep,
            .incb_linker_after_consonant = st.incb_linker_after_consonant,
            .incb_seen_consonant = st.incb_seen_consonant,
        };
    }

    fn encode(cs: ClusterState) u9 {
        const st = State{
            .previous = @backingInt(cs.previous),
            .ri_parity = cs.ri_count % 2 == 1,
            .ep_before_zwj = cs.ep_before_zwj,
            .zwj_after_ep = cs.zwj_after_ep,
            .incb_seen_consonant = cs.incb_seen_consonant,
            .incb_linker_after_consonant = cs.incb_linker_after_consonant,
        };
        return @bitCast(st);
    }

    const Raw = struct { brk: bool, next: u9 };

    fn rawStep(id: u9, cat: usize) Raw {
        const c = catalogue.items[cat];
        var cs = reference(id);
        const brk = cs.breakBeforeNext(c);
        if (brk) cs = ClusterState.init(c) else cs.consume(c);
        return .{ .brk = brk, .next = encode(cs) };
    }

    /// Breadth-first reachability from the states a cluster can start in.
    /// Only 4 of the 9 encoded bits vary independently in practice, so this
    /// cuts the table by an order of magnitude.
    const reach = blk: {
        @setEvalBranchQuota(20000000);
        var dense: [state_count]i16 = @splat(-1);
        var order: [state_count]u9 = undefined;
        var len: usize = 0;
        for (0..category_count) |cat| {
            const s = encode(ClusterState.init(catalogue.items[cat]));
            if (dense[s] < 0) {
                dense[s] = @intCast(len);
                order[len] = s;
                len += 1;
            }
        }
        var head: usize = 0;
        while (head < len) : (head += 1) {
            const cur = order[head];
            for (0..category_count) |cat| {
                const n = rawStep(cur, cat).next;
                if (dense[n] < 0) {
                    dense[n] = @intCast(len);
                    order[len] = n;
                    len += 1;
                }
            }
        }
        break :blk .{ .dense = dense, .order = order, .len = len };
    };

    pub const reachable_states = reach.len;

    /// Entry: bit 0 is "break before this scalar", bits 1.. are the successor.
    /// On a break the successor is `init(category)`, so one read both decides
    /// the boundary and positions the state for the next cluster.
    pub const transitions = blk: {
        @setEvalBranchQuota(20000000);
        var table: [reachable_states * category_count]u8 = @splat(0);
        for (0..reachable_states) |d| {
            for (0..category_count) |cat| {
                const r = rawStep(reach.order[d], cat);
                table[d * category_count + cat] =
                    (@as(u8, @intCast(reach.dense[r.next])) << 1) | @intFromBool(r.brk);
            }
        }
        break :blk table;
    };

    /// State a fresh cluster is in after its first scalar, as a dense id.
    pub const initial_of = blk: {
        @setEvalBranchQuota(200000);
        var table: [category_count]u8 = @splat(0);
        for (0..category_count) |cat|
            table[cat] = @intCast(reach.dense[encode(ClusterState.init(catalogue.items[cat]))]);
        break :blk table;
    };

    pub const data_bytes = @sizeOf(@TypeOf(transitions)) + @sizeOf(@TypeOf(category_of)) + @sizeOf(@TypeOf(initial_of));

    comptime {
        // Plan 019 budget. The table is built from the reference rules at
        // comptime, so a rule change moves these numbers rather than silently
        // diverging; if it trips, re-check the budget, do not widen it.
        if (data_bytes > 16 * 1024) @compileError("grapheme machine exceeds 16 KiB");
        if (reachable_states > 128) @compileError("successor no longer fits 7 bits");
    }
};

/// Category for an already-decoded scalar: one bitcast of the property bits
/// `decoded_token.at` unpacked, plus one 128-byte lookup.
pub inline fn categoryOf(token: decoded_token.Token) u8 {
    return machine.category_of[@as(u7, @bitCast(token.grapheme))];
}

/// Internal bridge for public streaming callers that already have a decoded
/// code point instead of a scalar token.
pub inline fn categoryForCodepoint(cp: u21) u8 {
    return machine.category_of[@as(u7, @bitCast(grapheme_properties.graphemeProperties(cp)))];
}

/// Table-driven cluster state. One read per scalar yields the boundary
/// decision and the successor.
pub const TableState = struct {
    id: u8,

    pub inline fn init(category: u8) TableState {
        return .{ .id = machine.initial_of[category] };
    }

    /// Returns whether the cluster ends before this scalar, and advances.
    pub inline fn step(self: *TableState, category: u8) bool {
        const entry = machine.transitions[@as(usize, self.id) * machine.category_count + category];
        self.id = entry >> 1;
        return entry & 1 == 1;
    }
};

fn isControl(p: Property) bool {
    return p == .cr or p == .lf or p == .control;
}

pub fn classify(token: decoded_token.Token) Classification {
    const property: Property = switch (token.grapheme.gcb) {
        .other => if (token.grapheme.extended_pictographic) .ep else .other,
        .regional_indicator => .ri,
        .spacingmark => .spacing_mark,
        else => @fromBackingInt(@intCast(@backingInt(token.grapheme.gcb))),
    };
    return .{
        .property = property,
        .incb = @fromBackingInt(@intCast(@backingInt(token.grapheme.incb))),
    };
}
