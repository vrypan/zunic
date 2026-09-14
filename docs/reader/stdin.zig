const std = @import("std");
const zunic = @import("zunic");

pub fn main(init: std.process.Init) !void {
    var buffer: [4096]u8 = undefined;
    var stdin = std.Io.File.stdin().readerStreaming(init.io, &buffer);
    const source = zunic.reader(&stdin.interface);
    var points = source.codepoints();
    while (try points.next()) |point| {
        std.debug.print("U+{X}\n", .{point.value});
    }
}
