//! Terminal-cell width policy shared by text measurement and rendering.
const table = @import("tables.zig");
const utf8 = @import("utf8.zig");
const grapheme = @import("grapheme.zig");

pub const Measure = struct {
    /// `0`, `1`, or `2` for renderable clusters; `3` marks a replacement.
    columns: u3,
    renderable: bool,
};

pub fn codepointWidth(cp: u21) u2 {
    if (cp < 0x300) return 1;
    if (inRanges(&table.zero_width, cp)) return 0;
    if (inRanges(&table.wide, cp)) return 2;
    return 1;
}

pub fn measureCluster(bytes: []const u8) Measure {
    var pos: usize = 0;
    var columns: usize = 0;
    var has_base = false;
    var has_pictograph = false;
    var has_ri = false;
    while (pos < bytes.len) {
        const s = utf8.step(bytes[pos..]);
        pos += s.len;
        const cp = s.cp orelse continue;
        if (cp < 0x20 or cp == 0x7f) continue;
        const w = codepointWidth(cp);
        if (w != 0) {
            has_base = true;
            columns += w;
        }
        if (grapheme.isExtendedPictographic(cp)) has_pictograph = true;
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
        const m = measureCluster(bytes[span.start..span.end]);
        total += if (m.columns == 3) 1 else m.columns;
    }
    return total;
}

fn inRanges(ranges: []const table.Range, cp: u21) bool {
    var lo: usize = 0;
    var hi: usize = ranges.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const r = ranges[mid];
        if (cp < r.lo) hi = mid else if (cp > r.hi) lo = mid + 1 else return true;
    }
    return false;
}
