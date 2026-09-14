//! Incremental grapheme snapshots over strict Reader codepoints.
const codepoint_view = @import("cp");
const segmentation = @import("segmentation");

pub const Span = struct {
    start: u64,
    end: u64,
};

pub const Update = struct {
    /// The current grapheme's cumulative byte extent.
    grapheme: Span,
    /// The scalar consumed for this update; null only for final EOF.
    point: ?codepoint_view.CodepointView,
    /// This scalar begins a new grapheme and finalizes the previous snapshot.
    starts_new: bool,
    /// Clean EOF has finalized this current grapheme.
    is_final: bool,
};

pub fn Iterator(comptime CodepointIterator: type) type {
    return struct {
        points: CodepointIterator,
        offset: u64 = 0,
        previous: ?u21 = null,
        state: segmentation.stream.GraphemeState = .{},
        current_start: u64 = 0,
        exhausted: bool = false,

        pub fn next(self: *@This()) CodepointIterator.Error!?Update {
            if (self.exhausted) return null;

            const scalar_start = self.points.offset;
            const maybe_point = try self.points.next();
            if (maybe_point) |point| {
                self.offset = self.points.offset;
                const starts_new = if (self.previous) |previous|
                    segmentation.stream.graphemeBreak(previous, point.value, &self.state)
                else
                    true;
                if (starts_new) self.current_start = scalar_start;
                self.previous = point.value;
                return .{
                    .grapheme = .{ .start = self.current_start, .end = self.offset },
                    .point = point,
                    .starts_new = starts_new,
                    .is_final = false,
                };
            }

            self.exhausted = true;
            if (self.previous == null) return null;
            return .{
                .grapheme = .{ .start = self.current_start, .end = self.offset },
                .point = null,
                .starts_new = false,
                .is_final = true,
            };
        }
    };
}
