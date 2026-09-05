//! Greedy terminal-column wrapping that preserves extended grapheme clusters.
const grapheme = @import("grapheme.zig");
const line_break = @import("line_break.zig");
const utf8 = @import("utf8.zig");
const width = @import("width.zig");
const ascii_scan = @import("ascii_scan.zig");

pub const Overflow = enum { allow, grapheme };
pub const Options = struct {
    max_columns: usize,
    overflow: Overflow = .grapheme,
};
pub const Line = struct { start: usize, end: usize, columns: usize };

const Candidate = struct {
    line: Line,
    graphemes: grapheme.Iterator,
    boundaries: line_break.Iterator,
};

pub const Iterator = struct {
    bytes: []const u8,
    options: Options,
    graphemes: grapheme.Iterator,
    boundaries: line_break.Iterator,
    line_start: usize = 0,
    columns: usize = 0,
    candidate: ?Candidate = null,
    ascii_only_letters: ?bool = null,
    finished: bool = false,

    pub fn next(self: *Iterator) ?Line {
        if (self.finished) return null;
        if (self.ascii_only_letters == null) self.ascii_only_letters = ascii_scan.allLetters(self.bytes);
        if (self.ascii_only_letters.?) return self.nextAsciiLetters();

        while (true) {
            const before_graphemes = self.graphemes;
            const before_boundaries = self.boundaries;
            const span = self.graphemes.next() orelse break;
            if (hardBreak(self.bytes[span.start..span.end])) {
                const line = Line{ .start = self.line_start, .end = span.start, .columns = self.columns };
                self.line_start = span.end;
                self.columns = 0;
                self.candidate = null;
                return line;
            }

            const measure = width.measureCluster(self.bytes[span.start..span.end]);
            const cluster_columns: usize = if (measure.columns == 3) 1 else measure.columns;
            const next_columns = self.columns + cluster_columns;
            const boundary = self.boundaryAt(span.end);
            const can_break = boundary.value.offset == span.end and boundary.value.opportunity != .prohibited;

            if (next_columns <= self.options.max_columns) {
                self.columns = next_columns;
                if (can_break) self.candidate = .{
                    .line = .{ .start = self.line_start, .end = span.end, .columns = self.columns },
                    .graphemes = self.graphemes,
                    .boundaries = boundary.before,
                };
                continue;
            }

            // The line is already wider than the limit because its first
            // cluster was oversized. Zero-column suffixes still belong to
            // that visual line.
            if (cluster_columns == 0 and self.columns > self.options.max_columns) {
                self.columns = next_columns;
                continue;
            }

            // A legal break that already fits is always preferable to an
            // overflow. `allow` only extends an unbreakable run when there
            // is no such break.
            if (self.candidate) |candidate| {
                self.graphemes = candidate.graphemes;
                self.boundaries = candidate.boundaries;
                self.line_start = candidate.line.end;
                self.columns = 0;
                self.candidate = null;
                return candidate.line;
            }

            switch (self.options.overflow) {
                .allow => {
                    self.columns = next_columns;
                    if (can_break) {
                        const line = Line{ .start = self.line_start, .end = span.end, .columns = self.columns };
                        self.line_start = span.end;
                        self.columns = 0;
                        self.candidate = null;
                        return line;
                    }
                },
                .grapheme => {
                    if (span.start == self.line_start) {
                        // Keep an oversized cluster pending. A following
                        // zero-column grapheme belongs to it, and a following
                        // hard terminator must be consumed before we return.
                        self.columns = next_columns;
                        continue;
                    }
                    const line = Line{ .start = self.line_start, .end = span.start, .columns = self.columns };
                    self.graphemes = before_graphemes;
                    self.boundaries = before_boundaries;
                    self.line_start = span.start;
                    self.columns = 0;
                    return line;
                },
            }
        }

        self.finished = true;
        if (self.line_start == self.bytes.len) return null;
        return .{ .start = self.line_start, .end = self.bytes.len, .columns = self.columns };
    }

    fn nextAsciiLetters(self: *Iterator) ?Line {
        if (self.line_start == self.bytes.len) {
            self.finished = true;
            return null;
        }
        const start = self.line_start;
        const end = switch (self.options.overflow) {
            .allow => self.bytes.len,
            .grapheme => @min(self.bytes.len, start + self.options.max_columns),
        };
        self.line_start = end;
        return .{ .start = start, .end = end, .columns = end - start };
    }

    const BoundaryAt = struct { value: line_break.Boundary, before: line_break.Iterator };

    fn boundaryAt(self: *Iterator, offset: usize) BoundaryAt {
        while (true) {
            const before = self.boundaries;
            const boundary = self.boundaries.next().?;
            if (boundary.offset >= offset) return .{ .value = boundary, .before = before };
        }
    }
};

pub fn iterator(bytes: []const u8, options: Options) error{InvalidWidth}!Iterator {
    if (options.max_columns == 0) return error.InvalidWidth;
    return .{
        .bytes = bytes,
        .options = options,
        .graphemes = grapheme.iterator(bytes),
        .boundaries = line_break.iterator(bytes),
    };
}

fn hardBreak(bytes: []const u8) bool {
    const cp = utf8.step(bytes).cp orelse return false;
    return switch (cp) {
        0x0B, 0x0C, 0x0D, 0x0A, 0x85, 0x2028, 0x2029 => true,
        else => false,
    };
}
