//! Greedy terminal-column wrapping that preserves extended grapheme clusters.
const grapheme = @import("grapheme.zig");
const line_break = @import("line_break.zig");
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
    ascii_paragraph: ?ascii_scan.Paragraph = null,
    finished: bool = false,

    pub fn next(self: *Iterator) ?Line {
        if (self.finished) return null;
        if (self.ascii_paragraph == null) self.ascii_paragraph = ascii_scan.paragraph(self.bytes);
        switch (self.ascii_paragraph.?) {
            .letters => return self.nextAsciiLetters(),
            .simple => return self.nextAsciiParagraph(),
            .none => {},
        }

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

            const cluster_columns = clusterColumns(self.bytes, span);
            const next_columns = self.columns + cluster_columns;
            const boundary = self.boundaryAt(span.end);
            const can_break = boundary.value.offset == span.end and boundary.value.opportunity != .prohibited;

            if (next_columns <= self.options.max_columns) {
                self.columns = next_columns;
                if (can_break) self.candidate = .{
                    .line = .{ .start = self.line_start, .end = span.end, .columns = self.columns },
                    .graphemes = self.graphemes,
                    // `boundaryAt` has consumed the boundary at span.end.
                    // Restoring after it avoids deciding that same boundary
                    // again when the next visual line starts there.
                    .boundaries = self.boundaries,
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

    fn nextAsciiParagraph(self: *Iterator) ?Line {
        if (self.line_start == self.bytes.len) {
            self.finished = true;
            return null;
        }
        const start = self.line_start;
        var pos = start;
        var columns: usize = 0;
        var candidate: ?Line = null;
        while (pos < self.bytes.len) {
            const byte = self.bytes[pos];
            if (byte == '\n' or byte == '\r' or byte == 0x0B or byte == 0x0C) {
                const end = if (byte == '\r' and pos + 1 < self.bytes.len and self.bytes[pos + 1] == '\n') pos + 2 else pos + 1;
                self.line_start = end;
                return .{ .start = start, .end = pos, .columns = columns };
            }
            // UAX #14 permits a break after a run of spaces, not between
            // adjacent spaces. Record the opportunity when the following
            // non-space confirms the end of that run.
            if (byte != ' ' and pos > start and self.bytes[pos - 1] == ' ') {
                candidate = .{ .start = start, .end = pos, .columns = columns };
            }
            const next_columns = columns + 1;
            if (next_columns <= self.options.max_columns) {
                columns = next_columns;
                pos += 1;
                continue;
            }
            if (candidate) |saved| {
                self.line_start = saved.end;
                return saved;
            }
            if (self.options.overflow == .allow) {
                columns = next_columns;
                pos += 1;
                continue;
            }
            if (pos == start) {
                columns = next_columns;
                pos += 1;
                continue;
            }
            self.line_start = pos;
            return .{ .start = start, .end = pos, .columns = columns };
        }
        self.finished = true;
        return .{ .start = start, .end = pos, .columns = columns };
    }

    const BoundaryAt = struct { value: line_break.Boundary };

    fn boundaryAt(self: *Iterator, offset: usize) BoundaryAt {
        while (true) {
            const boundary = self.boundaries.next().?;
            if (boundary.offset >= offset) return .{ .value = boundary };
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
    return switch (bytes[0]) {
        0x0A, 0x0B, 0x0C, 0x0D => true,
        0xC2 => bytes.len >= 2 and bytes[1] == 0x85,
        0xE2 => bytes.len >= 3 and bytes[1] == 0x80 and (bytes[2] == 0xA8 or bytes[2] == 0xA9),
        else => false,
    };
}

/// Grapheme iteration has already established that this is one cluster. For a
/// one-byte ASCII cluster, terminal width is determined without decoding it or
/// consulting emoji properties. All other clusters retain the shared width
/// policy verbatim.
fn clusterColumns(bytes: []const u8, span: grapheme.Span) usize {
    if (span.end == span.start + 1) {
        const byte = bytes[span.start];
        if (byte < 0x20 or byte == 0x7f) return 0;
        if (byte < 0x80) return 1;
    }
    return if (span.columns == 3) 1 else span.columns;
}
