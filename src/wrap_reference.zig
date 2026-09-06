//! Deliberately simple, allocating reference implementation for wrap tests.
const std = @import("std");
const unicode = @import("zunic");

const Cluster = struct {
    start: usize,
    end: usize,
    columns: usize,
    can_break: bool,
    hard: bool,
};

pub const Line = struct { start: usize, end: usize, columns: usize };

pub fn collect(allocator: std.mem.Allocator, bytes: []const u8, options: unicode.WrapOptions) ![]Line {
    if (options.max_columns == 0) return error.InvalidWidth;

    var clusters: std.ArrayList(Cluster) = .empty;
    defer clusters.deinit(allocator);

    var boundaries = unicode.line_break.iterator(bytes);
    var boundary = boundaries.next();
    var graphemes = unicode.graphemes(bytes).measured().iterator();
    while (graphemes.next()) |span| {
        while (boundary) |value| {
            if (value.offset >= span.end.value) break;
            boundary = boundaries.next();
        }
        try clusters.append(allocator, .{
            .start = span.start.value,
            .end = span.end.value,
            .columns = span.columns,
            .can_break = boundary != null and boundary.?.offset == span.end.value and boundary.?.opportunity != .prohibited,
            .hard = isHard(bytes[span.start.value..span.end.value]),
        });
    }

    var result: std.ArrayList(Line) = .empty;
    errdefer result.deinit(allocator);
    var index: usize = 0;
    var line_start: usize = 0;
    var columns: usize = 0;
    var candidate: ?struct { end_index: usize, line: Line } = null;

    while (index < clusters.items.len) {
        const cluster = clusters.items[index];
        if (cluster.hard) {
            try result.append(allocator, .{ .start = line_start, .end = cluster.start, .columns = columns });
            index += 1;
            line_start = cluster.end;
            columns = 0;
            candidate = null;
            continue;
        }

        const next_columns = columns + cluster.columns;
        if (next_columns <= options.max_columns) {
            columns = next_columns;
            index += 1;
            if (cluster.can_break) candidate = .{ .end_index = index, .line = .{ .start = line_start, .end = cluster.end, .columns = columns } };
            continue;
        }

        if (cluster.columns == 0 and columns > options.max_columns) {
            columns = next_columns;
            index += 1;
            continue;
        }

        if (candidate) |saved| {
            try result.append(allocator, saved.line);
            index = saved.end_index;
            line_start = saved.line.end;
            columns = 0;
            candidate = null;
            continue;
        }

        switch (options.overflow) {
            .allow => {
                columns = next_columns;
                index += 1;
                if (cluster.can_break) {
                    try result.append(allocator, .{ .start = line_start, .end = cluster.end, .columns = columns });
                    line_start = cluster.end;
                    columns = 0;
                }
            },
            .grapheme => {
                if (cluster.start == line_start) {
                    columns = next_columns;
                    index += 1;
                } else {
                    try result.append(allocator, .{ .start = line_start, .end = cluster.start, .columns = columns });
                    line_start = cluster.start;
                    columns = 0;
                }
            },
        }
    }

    if (line_start != bytes.len) try result.append(allocator, .{ .start = line_start, .end = bytes.len, .columns = columns });
    return result.toOwnedSlice(allocator);
}

fn isHard(bytes: []const u8) bool {
    const cp = unicode.utf8.step(bytes).cp orelse return false;
    return switch (cp) {
        0x0B, 0x0C, 0x0D, 0x0A, 0x85, 0x2028, 0x2029 => true,
        else => false,
    };
}
