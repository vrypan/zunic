//! Terminal-cell width policy shared by text measurement and rendering.
const grapheme = @import("grapheme.zig");
const scalar = @import("scalar.zig");

pub const Measure = struct {
    /// `0`, `1`, or `2` for renderable clusters; `3` marks a replacement.
    columns: u3,
    renderable: bool,
};

pub fn codepointWidth(cp: u21) u2 {
    return scalar.codepointWidth(cp);
}

pub fn measureCluster(bytes: []const u8) Measure {
    var tokens = scalar.iterator(bytes);
    var columns: usize = 0;
    var has_base = false;
    var has_pictograph = false;
    var has_ri = false;
    while (tokens.next()) |token| {
        const cp = token.codepoint orelse continue;
        if (cp < 0x20 or cp == 0x7f) continue;
        const w = token.cell_width;
        if (w != 0) {
            has_base = true;
            columns += w;
        }
        if (token.grapheme.extended_pictographic) has_pictograph = true;
        if (cp >= 0x1f1e6 and cp <= 0x1f1ff) has_ri = true;
    }
    if (!has_base) return .{ .columns = 0, .renderable = false };
    if (has_pictograph or has_ri) return .{ .columns = 2, .renderable = true };
    if (columns > 2) return .{ .columns = 3, .renderable = false };
    return .{ .columns = @intCast(columns), .renderable = true };
}

/// Width after terminal filtering. Invalid bytes and control characters are
/// dropped, matching Screen; emoji sequences are measured as one cluster.
pub fn textWidth(bytes: []const u8) usize {
    var it = grapheme.iterator(bytes);
    var total: usize = 0;
    while (it.next()) |span| {
        total += if (span.columns == 3) 1 else span.columns;
    }
    return total;
}
