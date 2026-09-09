//! Active text formatting, not a terminal screen or command history.
const std = @import("std");

pub const State = struct {
    foreground: Color = .default,
    background: Color = .default,
    underline_color: Color = .default,
    bold: bool = false,
    faint: bool = false,
    italic: bool = false,
    fraktur: bool = false,
    inverse: bool = false,
    concealed: bool = false,
    strikethrough: bool = false,
    overline: bool = false,
    proportional: bool = false,
    underline: Underline = .none,
    blink: Blink = .none,
    frame: Frame = .none,
    font: Font = .default,
    script: Script = .normal,
    ideogram: Ideogram = .{},
    /// OSC 8 data borrows the iterator input. SGR resets do not close links.
    link: ?Link = null,

    pub const Color = union(enum) {
        default,
        indexed: u8,
        rgb: struct { r: u8, g: u8, b: u8 },
    };
    pub const Underline = enum { none, single, double, curly, dotted, dashed };
    pub const Blink = enum { none, slow, rapid };
    pub const Frame = enum { none, framed, encircled };
    pub const Font = enum { default, alternate_1, alternate_2, alternate_3, alternate_4, alternate_5, alternate_6, alternate_7, alternate_8, alternate_9 };
    pub const Script = enum { normal, superscript, subscript };
    pub const Ideogram = struct {
        underline: bool = false,
        double_underline: bool = false,
        overline: bool = false,
        double_overline: bool = false,
        stress: bool = false,
    };
    pub const Link = struct {
        /// Full parameter string, including id= and any unknown parameters.
        params: []const u8,
        uri: []const u8,
    };
};

/// Fields assigned by an SGR command, even if their values were already equal.
/// unhandled reports unsupported, invalid, or incomplete parameters.
pub const StyleFields = packed struct {
    foreground: bool = false,
    background: bool = false,
    underline_color: bool = false,
    bold: bool = false,
    faint: bool = false,
    italic: bool = false,
    fraktur: bool = false,
    inverse: bool = false,
    concealed: bool = false,
    strikethrough: bool = false,
    overline: bool = false,
    proportional: bool = false,
    underline: bool = false,
    blink: bool = false,
    frame: bool = false,
    font: bool = false,
    script: bool = false,
    ideogram: bool = false,
    unhandled: bool = false,
};

fn markUnhandled(fields: StyleFields) StyleFields {
    var result = fields;
    result.unhandled = true;
    return result;
}

fn assign(state: *State, fields: *StyleFields, comptime name: []const u8, value: @FieldType(State, name)) void {
    @field(state, name) = value;
    @field(fields, name) = true;
}

// Called only with recognized numeric SGR. Parse without allocating or keeping
// an unbounded list of parameters. Unknown subparameters stay in their group.
pub fn applySgr(state: *State, bytes: []const u8) StyleFields {
    var fields: StyleFields = .{};
    var groups = std.mem.splitScalar(u8, bytes[2 .. bytes.len - 1], ';');
    while (groups.next()) |group| {
        if (std.mem.indexOfScalar(u8, group, ':') != null) {
            if (!applyColon(state, &fields, group)) fields.unhandled = true;
            continue;
        }
        const code = if (group.len == 0) 0 else number(group) orelse {
            fields.unhandled = true;
            continue;
        };
        switch (code) {
            0 => {
                state.* = .{ .link = state.link };
                inline for (@typeInfo(StyleFields).@"struct".fields) |field| {
                    if (comptime !std.mem.eql(u8, field.name, "unhandled")) @field(fields, field.name) = true;
                }
            },
            1 => assign(state, &fields, "bold", true),
            2 => assign(state, &fields, "faint", true),
            3 => assign(state, &fields, "italic", true),
            4 => assign(state, &fields, "underline", .single),
            5 => assign(state, &fields, "blink", .slow),
            6 => assign(state, &fields, "blink", .rapid),
            7 => assign(state, &fields, "inverse", true),
            8 => assign(state, &fields, "concealed", true),
            9 => assign(state, &fields, "strikethrough", true),
            10...19 => assign(state, &fields, "font", @enumFromInt(code - 10)),
            20 => assign(state, &fields, "fraktur", true),
            21 => assign(state, &fields, "underline", .double),
            22 => {
                assign(state, &fields, "bold", false);
                assign(state, &fields, "faint", false);
            },
            23 => {
                assign(state, &fields, "italic", false);
                assign(state, &fields, "fraktur", false);
            },
            24 => assign(state, &fields, "underline", .none),
            25 => assign(state, &fields, "blink", .none),
            26 => assign(state, &fields, "proportional", true),
            27 => assign(state, &fields, "inverse", false),
            28 => assign(state, &fields, "concealed", false),
            29 => assign(state, &fields, "strikethrough", false),
            30...37 => assign(state, &fields, "foreground", .{ .indexed = @intCast(code - 30) }),
            40...47 => assign(state, &fields, "background", .{ .indexed = @intCast(code - 40) }),
            90...97 => assign(state, &fields, "foreground", .{ .indexed = @intCast(code - 90 + 8) }),
            100...107 => assign(state, &fields, "background", .{ .indexed = @intCast(code - 100 + 8) }),
            38, 48, 58 => {
                // A bad/unknown mode has no known group length. Stop this SGR
                // rather than interpreting possible color data as attributes.
                const mode = number(groups.next() orelse return markUnhandled(fields)) orelse return markUnhandled(fields);
                switch (mode) {
                    5 => {
                        const value = component(groups.next() orelse return markUnhandled(fields)) orelse {
                            fields.unhandled = true;
                            continue;
                        };
                        colorTarget(state, &fields, code).* = .{ .indexed = value };
                    },
                    2 => {
                        const r = component(groups.next() orelse return markUnhandled(fields));
                        const g = component(groups.next() orelse return markUnhandled(fields));
                        const b = component(groups.next() orelse return markUnhandled(fields));
                        if (r != null and g != null and b != null) {
                            colorTarget(state, &fields, code).* = .{ .rgb = .{ .r = r.?, .g = g.?, .b = b.? } };
                        } else fields.unhandled = true;
                    },
                    else => return markUnhandled(fields),
                }
            },
            39 => assign(state, &fields, "foreground", .default),
            49 => assign(state, &fields, "background", .default),
            50 => assign(state, &fields, "proportional", false),
            51 => assign(state, &fields, "frame", .framed),
            52 => assign(state, &fields, "frame", .encircled),
            53 => assign(state, &fields, "overline", true),
            54 => assign(state, &fields, "frame", .none),
            55 => assign(state, &fields, "overline", false),
            59 => assign(state, &fields, "underline_color", .default),
            60 => {
                state.ideogram.underline = true;
                fields.ideogram = true;
            },
            61 => {
                state.ideogram.double_underline = true;
                fields.ideogram = true;
            },
            62 => {
                state.ideogram.overline = true;
                fields.ideogram = true;
            },
            63 => {
                state.ideogram.double_overline = true;
                fields.ideogram = true;
            },
            64 => {
                state.ideogram.stress = true;
                fields.ideogram = true;
            },
            65 => assign(state, &fields, "ideogram", .{}),
            73 => assign(state, &fields, "script", .superscript),
            74 => assign(state, &fields, "script", .subscript),
            75 => assign(state, &fields, "script", .normal),
            else => fields.unhandled = true,
        }
    }
    return fields;
}

fn number(bytes: []const u8) ?u16 {
    if (bytes.len == 0) return null;
    var result: u16 = 0;
    for (bytes) |byte| {
        if (byte < '0' or byte > '9') return null;
        const digit: u16 = byte - '0';
        if (result > (std.math.maxInt(u16) - digit) / 10) return null;
        result = result * 10 + digit;
    }
    return result;
}

fn component(bytes: []const u8) ?u8 {
    const value = number(bytes) orelse return null;
    return if (value <= 255) @intCast(value) else null;
}

fn colorTarget(state: *State, fields: *StyleFields, code: u16) *State.Color {
    return switch (code) {
        38 => blk: {
            fields.foreground = true;
            break :blk &state.foreground;
        },
        48 => blk: {
            fields.background = true;
            break :blk &state.background;
        },
        58 => blk: {
            fields.underline_color = true;
            break :blk &state.underline_color;
        },
        else => unreachable,
    };
}

fn applyColon(state: *State, fields: *StyleFields, group: []const u8) bool {
    var parts = std.mem.splitScalar(u8, group, ':');
    const code = number(parts.next().?) orelse return false;
    const mode = number(parts.next() orelse return false) orelse return false;
    if (code == 4) {
        if (mode > 5 or parts.next() != null) return false;
        assign(state, fields, "underline", @enumFromInt(mode));
        return true;
    }
    if (code != 38 and code != 48 and code != 58) return false;
    if (mode == 5) {
        const index = component(parts.next() orelse return false) orelse return false;
        if (parts.next() != null) return false;
        colorTarget(state, fields, code).* = .{ .indexed = index };
        return true;
    } else if (mode == 2) {
        const first = parts.next() orelse return false;
        const second = parts.next() orelse return false;
        const third = parts.next() orelse return false;
        const fourth = parts.next();
        // RGB with no color-space slot, or with an empty/zero slot.
        if (fourth != null and (first.len != 0 and number(first) != 0)) return false;
        if (parts.next() != null) return false;
        const r = component(if (fourth != null) second else first) orelse return false;
        const g = component(if (fourth != null) third else second) orelse return false;
        const b = component(fourth orelse third) orelse return false;
        colorTarget(state, fields, code).* = .{ .rgb = .{ .r = r, .g = g, .b = b } };
        return true;
    }
    return false;
}

// Called only with a recognized non-SGR escape. True means an OSC 8 update;
// its two borrowed slices retain arbitrary URI and parameter lengths.
pub fn applyOther(state: *State, bytes: []const u8) bool {
    if (!std.mem.startsWith(u8, bytes, "\x1b]8;")) return false;
    const end = bytes.len - @as(usize, if (bytes[bytes.len - 1] == 0x07) 1 else 2);
    const payload = bytes[4..end];
    const separator = std.mem.indexOfScalar(u8, payload, ';') orelse return false;
    const uri = payload[separator + 1 ..];
    state.link = if (uri.len == 0) null else .{ .params = payload[0..separator], .uri = uri };
    return true;
}
