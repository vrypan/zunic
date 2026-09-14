const std = @import("std");
const zunic = @import("zunic");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    var stdin_buffer: [4096]u8 = undefined;
    var stdin = std.Io.File.stdin().readerStreaming(init.io, &stdin_buffer);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &stdout_buffer);
    defer stdout.interface.flush() catch {};

    var current: std.ArrayList(u8) = .empty;
    defer current.deinit(allocator);

    var graphemes = zunic.reader(&stdin.interface).graphemes();
    while (try graphemes.next()) |update| {
        if (update.starts_new and current.items.len != 0) {
            try stdout.interface.writeAll(current.items);
            try stdout.interface.writeByte('\n');
            try stdout.interface.flush();
            current.clearRetainingCapacity();
        }
        if (update.point) |point| {
            var encoded: [4]u8 = undefined;
            const len = try std.unicode.utf8Encode(point.value, &encoded);
            try current.appendSlice(allocator, encoded[0..len]);
        }
        if (update.is_final) {
            try stdout.interface.writeAll(current.items);
            try stdout.interface.writeByte('\n');
            current.clearRetainingCapacity();
        }
    }
    try stdout.interface.flush();
}
