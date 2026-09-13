const std = @import("std");
const zunic = @import("zunic");

pub fn main(init: std.process.Init) !void {
    var buffer: [64 * 1024]u8 = undefined;
    var file = std.Io.File.stdout().writer(init.io, &buffer);
    const out = &file.interface;
    for (0..0x200000) |raw| {
        const point = zunic.cp(@intCast(raw));
        const props = point.bidi();
        const mirror = point.bidiMirroringGlyph();
        const bracket = point.bidiPairedBracket();
        const mirror_value: u21 = mirror orelse 0;
        const bracket_value: u21 = bracket orelse 0;
        const record = [9]u8{
            @bitCast(props),
            @intFromBool(mirror != null),
            @truncate(mirror_value),
            @truncate(mirror_value >> 8),
            @truncate(mirror_value >> 16),
            @intFromBool(bracket != null),
            @truncate(bracket_value),
            @truncate(bracket_value >> 8),
            @truncate(bracket_value >> 16),
        };
        try out.writeAll(&record);
    }
    try out.flush();
}
