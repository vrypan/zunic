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
    return mixedTextWidth(bytes);
}

/// ASCII runs measured wholesale, the rest handed to the grapheme engine.
///
/// The retreat is the load-bearing part. An ASCII byte can be the base of a
/// cluster that continues into non-ASCII -- `a` + U+0301 is one cluster -- so
/// the run's last byte is given back to the engine rather than counted here.
/// It is a safe handover point because only CRLF pairs among ASCII bytes, so
/// every other ASCII byte begins a cluster.
///
/// Retreating to a *scalar* start instead would be wrong:
/// `a` + U+0903 + U+0903 is one cluster of one column that splits into 1 + 2.
/// How many probes may come back nearly empty before the fast path gives up.
///
/// Dense non-ASCII pays the vector load and compare on every chunk and then
/// hands the whole thing to the engine anyway, which measured 5-13% slower on
/// Korean, Japanese, Hindi and Russian. Once a buffer has shown it is that
/// shape, stop asking. Correctness never depends on this: giving up only
/// routes the remainder through the engine, which is the answer either way.
const probe_giveup = 8;
/// A run shorter than one vector was not worth the probe that found it.
const probe_worthwhile = 16;

noinline fn mixedTextWidth(bytes: []const u8) usize {
    var total: usize = 0;
    var pos: usize = 0;
    var barren: usize = 0;
    while (pos < bytes.len) {
        if (barren >= probe_giveup) return total + generalWidthFrom(bytes, pos);
        const run = ascii_scan.asciiRun(bytes, pos);
        barren = if (run.end - pos >= probe_worthwhile) 0 else barren + 1;
        if (run.end >= bytes.len) return total + run.columns;

        var resync = run.end;
        if (resync > pos) {
            total += run.columns;
            resync -= 1;
            if (bytes[resync] >= 0x20 and bytes[resync] != 0x7F) total -= 1;
        } else if (pos > 0) {
            // The run was empty, so the byte before `pos` was counted by an
            // earlier pass; its cluster reaches past `pos`, so take it back.
            resync = pos - 1;
            if (bytes[resync] >= 0x20 and bytes[resync] != 0x7F) total -= 1;
        }

        // The engine owns the region until a cluster ends on an ASCII byte,
        // which is by construction a cluster boundary the run can resume from.
        var it = grapheme.iterator(bytes[resync..]);
        var resumed = false;
        while (it.next()) |span| {
            total += grapheme.displayColumns(span.columns);
            const end = resync + span.end;
            if (end >= bytes.len) break;
            if (bytes[end] < 0x80) {
                pos = end;
                resumed = true;
                break;
            }
        }
        if (!resumed) return total;
    }
    return total;
}

/// `start` must be a cluster boundary, which every caller here holds: it is
/// either zero or a cluster end the engine just reported.
fn generalWidthFrom(bytes: []const u8, start: usize) usize {
    var it = grapheme.iterator(bytes[start..]);
    var total: usize = 0;
    while (it.next()) |span| total += grapheme.displayColumns(span.columns);
    return total;
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
