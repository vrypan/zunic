//! Unicode 16 semantic machine: each consume is a generated state transition.
//! Decisions are pure queries; only LB15b/c, LB19a, LB25 and LB28a look ahead.
const properties = @import("tables").properties;
const data = @import("tables").line_break_machine_data;
const Class = properties.LineBreak;

pub const Opportunity = enum { prohibited, allowed, mandatory };

pub inline fn categoryFor(_: u21, r: properties.Record) u8 {
    return r.line_break_category;
}

pub const State = struct {
    id: u8 = 0,

    pub fn firstWithRecord(_: Class, cp: u21, r: properties.Record) State {
        var self = State{};
        self.consumeRecord(cp, r);
        return self;
    }

    fn entry(self: *const State, cp: u21, r: properties.Record) u16 {
        return self.entryCategory(categoryFor(cp, r));
    }

    inline fn entryCategory(self: *const State, category: u8) u16 {
        return data.transitions[@as(usize, self.id) * data.category_count + category];
    }

    pub fn consumeRecord(self: *State, cp: u21, r: properties.Record) void {
        self.id = @truncate(self.entry(cp, r));
    }

    pub inline fn consumeCategory(self: *State, category: u8) void {
        self.id = @truncate(self.entryCategory(category));
    }

    /// Advance using the same entry that supplies the boundary action. The
    /// public iterator uses this combined operation so category construction
    /// and transition lookup happen once per consumed scalar.
    pub inline fn consumeAndOpcode(self: *State, cp: u21, r: properties.Record) u8 {
        return self.consumeCategoryAndOpcode(categoryFor(cp, r));
    }

    pub inline fn consumeCategoryAndOpcode(self: *State, category: u8) u8 {
        const value = self.entryCategory(category);
        self.id = @truncate(value);
        return @truncate(value >> 8);
    }

    pub fn opportunityForRecord(self: *const State, bytes: []const u8, cp: u21, r: properties.Record, next_raw: Class, next_record: properties.Record, has_next: bool, next_end: usize, classifier: anytype) Opportunity {
        const opcode = self.entry(cp, r) >> 8;
        return opportunityForOpcode(@truncate(opcode), bytes, next_raw, next_record, has_next, next_end, classifier);
    }

    pub inline fn opportunityForCategory(self: *const State, input_category: u8, bytes: []const u8, next_raw: Class, next_record: properties.Record, has_next: bool, next_end: usize, classifier: anytype) Opportunity {
        return opportunityForOpcode(@truncate(self.entryCategory(input_category) >> 8), bytes, next_raw, next_record, has_next, next_end, classifier);
    }

    pub inline fn opportunityForOpcode(opcode: u8, bytes: []const u8, next_raw: Class, next_record: properties.Record, has_next: bool, next_end: usize, classifier: anytype) Opportunity {
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
    if (@sizeOf(@TypeOf(data.transitions)) > 32 * 1024)
        @compileError("semantic line-break data exceeds 32 KiB");
}
