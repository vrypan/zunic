//! Unicode 16 semantic machine: each consume is a generated state transition.
//! Decisions are pure queries; only LB15b/c, LB19a, LB25 and LB28a look ahead.
const properties = @import("properties.zig");
const data = @import("line_break_machine_data.zig");
const Class = properties.LineBreak;

pub const Opportunity = enum { prohibited, allowed, mandatory };

fn category(cp: u21, r: properties.Record) u8 {
    const special = switch (r.line_break) {
        .qu => r.lb_qu_pi,
        .op => r.lb_op30,
        .cp => r.lb_cp30,
        .sa => r.lb_sa_mn_mc,
        .ba => cp == 0x2010,
        .al => cp == 0x25CC,
        else => r.ep_cn,
    };
    const key = @as(usize, @intFromEnum(r.line_break)) * 8 +
        @as(usize, @intFromBool(r.east_asian_wide)) +
        2 * @as(usize, @intFromBool(special)) +
        4 * @as(usize, @intFromBool(r.line_break == .qu and r.lb_qu_pf));
    const result = data.category_map[key];
    if (result == 255) unreachable; // Generator verifies all scalar categories.
    return result;
}

pub const State = struct {
    id: u8 = 0,

    pub fn firstWithRecord(_: Class, cp: u21, r: properties.Record) State {
        var self = State{};
        self.consumeRecord(cp, r);
        return self;
    }

    fn entry(self: *const State, cp: u21, r: properties.Record) u16 {
        return data.transitions[@as(usize, self.id) * data.category_count + category(cp, r)];
    }

    pub fn consumeRecord(self: *State, cp: u21, r: properties.Record) void {
        self.id = @truncate(self.entry(cp, r));
    }

    pub fn opportunityForRecord(self: *const State, bytes: []const u8, cp: u21, r: properties.Record, next_raw: Class, next_record: properties.Record, has_next: bool, next_end: usize, classifier: anytype) Opportunity {
        const opcode = self.entry(cp, r) >> 8;
        return switch (opcode) {
            0 => .prohibited,
            1 => .allowed,
            2 => .mandatory,
            3 => if (has_next and next_raw == .nu) .allowed else .prohibited,
            4 => if (!has_next or quoteFollower(next_raw)) .prohibited else .allowed,
            5 => if (has_next and (next_raw == .nu or (next_raw == .is and classifier.at(bytes, next_end).record.line_break == .nu))) .prohibited else .allowed,
            6 => if (has_next and next_record.east_asian_wide) .allowed else .prohibited,
            7 => if (has_next and next_raw == .vf) .prohibited else .allowed,
            else => unreachable,
        };
    }
};

fn quoteFollower(c: Class) bool {
    return switch (c) {
        .bk, .cr, .lf, .nl, .sp, .gl, .wj, .cl, .qu, .cp, .ex, .is, .sy, .zw => true,
        else => false,
    };
}

comptime {
    if (@sizeOf(@TypeOf(data.transitions)) + @sizeOf(@TypeOf(data.category_map)) > 32 * 1024)
        @compileError("semantic line-break data exceeds 32 KiB");
}
