//! Greedy terminal-column wrapping that preserves extended grapheme clusters.
//!
//! The general path is driven by `scan.Scanner`, which decodes each scalar
//! once. The wrapper itself never rewinds it: the most recent fitting break
//! is kept as a plain `Line` plus the column count accumulated since it, and
//! an overflow step emits at most one extra buffered line. Total work is
//! therefore bounded by the scanner's per-scalar bound, independent of
//! `max_columns` and of how many lines are consumed.
const scan = @import("scan.zig");
const ascii_scan = @import("ascii_scan.zig");
const grapheme = @import("segmentation").grapheme;

pub const Overflow = enum { allow, grapheme };
pub const Options = struct {
    max_columns: usize,
    overflow: Overflow = .grapheme,
};
pub const Line = struct { start: usize, end: usize, columns: usize };

pub const Iterator = IteratorImpl(false);
/// Test-only variant whose scanner counts decoded scalars and buffered
/// tokens so the work bound can be asserted; identical behavior otherwise.
pub const InstrumentedIterator = IteratorImpl(true);

fn IteratorImpl(comptime instrumented: bool) type {
    return struct {
        bytes: []const u8,
        options: Options,
        scanner: scan.Scanner(instrumented),
        line_start: usize = 0,
        columns: usize = 0,
        candidate: ?Line = null,
        pending_line: ?Line = null,
        ascii_paragraph: ?ascii_scan.Paragraph = null,
        finished: bool = false,
        /// Set when a whole-line shortcut emitted a line without advancing
        /// `scanner`, so the next fallback knows to reposition it.
        scanner_stale: bool = false,

        const Self = @This();

        pub inline fn next(self: *Self) ?Line {
            if (self.ascii_paragraph == null) self.ascii_paragraph = ascii_scan.paragraph(self.bytes);
            switch (self.ascii_paragraph.?) {
                // The ASCII consumers keep their own termination state and
                // never buffer a pending line, so they skip those checks.
                .letters => return self.nextAsciiLetters(),
                .simple => return self.nextAsciiParagraph(),
                .none => return self.nextMixed(),
            }
        }

        /// A line that already fits needs no break, and a line that needs no
        /// break needs no break *opportunities* -- so this path is open to any
        /// ASCII, not just `isSimple`'s alphabet. That is the whole point:
        /// source code fails `paragraph` on `(`, `-` and tab, yet almost every
        /// one of its lines is far shorter than the limit.
        ///
        /// Only attempted from a clean line start. Mid-line the general path
        /// holds state -- a carried column count, a candidate break, a pending
        /// line -- that this cannot reproduce.
        noinline fn nextMixed(self: *Self) ?Line {
            if (self.pending_line == null and !self.finished and
                self.columns == 0 and self.candidate == null and
                self.line_start < self.bytes.len)
            {
                if (ascii_scan.asciiLine(self.bytes, self.line_start)) |line| {
                    if (line.columns <= self.options.max_columns) {
                        const result: Line = .{ .start = self.line_start, .end = line.end, .columns = line.columns };
                        self.line_start = line.end + line.terminator_len;
                        // The scanner did not move, so it no longer describes
                        // `line_start`; the next fallback repositions it.
                        self.scanner_stale = true;
                        if (self.line_start == self.bytes.len and line.terminator_len == 0) self.finished = true;
                        return result;
                    }
                }
            }
            if (self.scanner_stale) {
                // Safe to restart the machine here rather than replay it: this
                // is a line start, and UAX #14 begins afresh after a mandatory
                // break, so no line-break context crosses the boundary.
                self.scanner = .{ .bytes = self.bytes, .decode_pos = self.line_start };
                self.scanner_stale = false;
            }
            return self.nextGeneral();
        }

        // Keep scanner code out of the ASCII dispatch's inlining budget.
        // Changing line-break backends must not change ASCII specialization.
        noinline fn nextGeneral(self: *Self) ?Line {
            if (self.pending_line) |line| {
                self.pending_line = null;
                return line;
            }
            if (self.finished) return null;

            while (self.scanner.next()) |cluster| {
                if (cluster.hard) {
                    const line = Line{ .start = self.line_start, .end = cluster.start, .columns = self.columns };
                    self.line_start = cluster.end;
                    self.columns = 0;
                    self.candidate = null;
                    return line;
                }

                const cluster_columns = grapheme.displayColumns(cluster.columns);
                const next_columns = self.columns + cluster_columns;
                const can_break = cluster.can_break;

                if (next_columns <= self.options.max_columns) {
                    self.columns = next_columns;
                    if (can_break) self.candidate = .{ .start = self.line_start, .end = cluster.end, .columns = self.columns };
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
                // is no such break. The scanner never rewinds: the tail
                // between the candidate and this cluster was already measured
                // (it holds no break opportunities, or one of them would have
                // become the candidate), so it carries over to the new line
                // as a column summary instead of being replayed.
                if (self.candidate) |line| {
                    self.candidate = null;
                    const tail_columns = self.columns - line.columns;
                    const new_columns = tail_columns + cluster_columns;
                    self.line_start = line.end;
                    if (new_columns <= self.options.max_columns) {
                        self.columns = new_columns;
                        if (can_break) self.candidate = .{ .start = self.line_start, .end = cluster.end, .columns = new_columns };
                        return line;
                    }
                    switch (self.options.overflow) {
                        .allow => {
                            self.columns = new_columns;
                            if (can_break) {
                                self.pending_line = .{ .start = self.line_start, .end = cluster.end, .columns = new_columns };
                                self.line_start = cluster.end;
                                self.columns = 0;
                            }
                        },
                        .grapheme => {
                            if (cluster.start == self.line_start) {
                                // The cluster alone overflows the new line;
                                // keep it pending for zero-column suffixes and
                                // hard terminators, exactly like an oversized
                                // first cluster reached without a candidate.
                                self.columns = new_columns;
                            } else {
                                self.pending_line = .{ .start = self.line_start, .end = cluster.start, .columns = tail_columns };
                                self.line_start = cluster.start;
                                self.columns = cluster_columns;
                                if (cluster_columns <= self.options.max_columns and can_break)
                                    self.candidate = .{ .start = cluster.start, .end = cluster.end, .columns = cluster_columns };
                            }
                        },
                    }
                    return line;
                }

                switch (self.options.overflow) {
                    .allow => {
                        self.columns = next_columns;
                        if (can_break) {
                            const line = Line{ .start = self.line_start, .end = cluster.end, .columns = self.columns };
                            self.line_start = cluster.end;
                            self.columns = 0;
                            return line;
                        }
                    },
                    .grapheme => {
                        if (cluster.start == self.line_start) {
                            // Keep an oversized cluster pending. A following
                            // zero-column grapheme belongs to it, and a
                            // following hard terminator must be consumed
                            // before we return.
                            self.columns = next_columns;
                            continue;
                        }
                        const line = Line{ .start = self.line_start, .end = cluster.start, .columns = self.columns };
                        self.line_start = cluster.start;
                        self.columns = cluster_columns;
                        if (cluster_columns <= self.options.max_columns and can_break)
                            self.candidate = .{ .start = cluster.start, .end = cluster.end, .columns = cluster_columns };
                        return line;
                    },
                }
            }

            self.finished = true;
            if (self.line_start == self.bytes.len) return null;
            return .{ .start = self.line_start, .end = self.bytes.len, .columns = self.columns };
        }

        inline fn nextAsciiLetters(self: *Self) ?Line {
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

        inline fn nextAsciiParagraph(self: *Self) ?Line {
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
                // non-space confirms the end of that run, unless the rules
                // forbid breaking in front of that character.
                if (byte != ' ' and pos > start and self.bytes[pos - 1] == ' ' and
                    !noBreakBefore(self.bytes, pos))
                {
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
            self.line_start = pos;
            return .{ .start = start, .end = pos, .columns = columns };
        }
    };
}

/// `. , ; :` are UAX #14 infix separators (class IS), which take no break in
/// front of them, except when a digit follows: LB25 then reads the pair as the
/// start of a number, where a break before it is allowed. The ASCII alphabet
/// in `ascii_scan.isSimple` is chosen so this is the only such exception.
fn noBreakBefore(bytes: []const u8, pos: usize) bool {
    return switch (bytes[pos]) {
        '.', ',', ';', ':' => !(pos + 1 < bytes.len and bytes[pos + 1] >= '0' and bytes[pos + 1] <= '9'),
        else => false,
    };
}

pub fn iterator(bytes: []const u8, options: Options) error{InvalidWidth}!Iterator {
    return open(false, bytes, options);
}

/// Test-only: `iterator` with decoded-scalar and buffer counters enabled.
pub fn instrumentedIterator(bytes: []const u8, options: Options) error{InvalidWidth}!InstrumentedIterator {
    return open(true, bytes, options);
}

/// The two constructors differ only in which instantiation they return, so the
/// width check lives here rather than being written out twice and drifting.
inline fn open(comptime instrumented: bool, bytes: []const u8, options: Options) error{InvalidWidth}!IteratorImpl(instrumented) {
    if (options.max_columns == 0) return error.InvalidWidth;
    return .{
        .bytes = bytes,
        .options = options,
        .scanner = .{ .bytes = bytes },
    };
}
