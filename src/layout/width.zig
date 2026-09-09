//! Terminal-cell width policy shared by text measurement and rendering.
const grapheme = @import("segmentation").grapheme;
const scalar = @import("encoding").scalar;
const ascii_scan = @import("ascii_scan.zig");

pub const Measure = struct {
    /// Renderable clusters occupy zero, one, or two columns.  Non-renderable
    /// input is explicit rather than encoded as an in-band sentinel.
    columns: u2,
    renderable: bool,
};

/// One definition of the policy, shared with the grapheme engine's in-pass
/// accumulator so a standalone measurement and a span can never drift apart.
pub fn measureCluster(bytes: []const u8) Measure {
    var tokens = scalar.iterator(bytes);
    var measure = grapheme.ClusterMeasure{};
    while (tokens.next()) |token| measure.add(token);
    // Both fields come from the one encoding, so neither restates it here.
    const columns = measure.finish();
    return .{
        .columns = @intCast(grapheme.displayColumns(columns)),
        .renderable = grapheme.isRenderable(columns),
    };
}

/// Width after terminal filtering. Invalid bytes and control characters are
/// dropped, matching Screen; emoji sequences are measured as one cluster.
pub fn textWidth(bytes: []const u8) usize {
    // Printable ASCII is one cluster of one column per byte, so the whole
    // measurement is the byte count.
    if (ascii_scan.allPrintable(bytes)) return bytes.len;
    return generalTextWidth(bytes);
}

// `grapheme.Iterator.next` is inline so each instantiation can drop the
// cluster measure it does not read. Keeping the loop out of line here stops
// that body from crowding the ASCII shortcut's inlining budget above, the same
// split `wrap.nextGeneral` makes for the same reason.
noinline fn generalTextWidth(bytes: []const u8) usize {
    var it = grapheme.iterator(bytes);
    var total: usize = 0;
    while (it.next()) |span| {
        total += grapheme.displayColumns(span.columns);
    }
    return total;
}
