//! Incremental grapheme bytes and boundaries over strict Reader codepoints.
const segmentation = @import("segmentation");
const decoded_token = @import("encoding").decoded_token;
const grapheme = segmentation.grapheme;

pub const Update = struct {
    /// Owned UTF-8 bytes of the scalar added by this update.
    _bytes: [4]u8 = .{ 0, 0, 0, 0 },
    _len: u3 = 0,
    /// These bytes begin a new grapheme and finalize the preceding grapheme.
    starts_new: bool,
    /// Clean EOF has finalized this current grapheme.
    is_final: bool,

    /// Newly consumed bytes, not the whole grapheme; empty at final EOF.
    /// The slice borrows this update and remains valid while it is alive.
    pub inline fn bytes(self: *const Update) []const u8 {
        return self._bytes[0..self._len];
    }
};

pub const MeasuredUpdate = struct {
    _bytes: [4]u8 = .{ 0, 0, 0, 0 },
    _len: u3 = 0,
    starts_new: bool,
    is_final: bool,
    /// Cumulative terminal columns for the current grapheme after these bytes.
    columns: u2 = 0,
    /// Whether that current grapheme fits Zunic's display policy.
    renderable: bool = false,

    /// Newly consumed bytes, borrowing this update; empty at final EOF.
    pub inline fn bytes(self: *const MeasuredUpdate) []const u8 {
        return self._bytes[0..self._len];
    }
};

pub fn Iterator(comptime CodepointIterator: type, comptime next_decoded: anytype, comptime include_measure: bool) type {
    return struct {
        const Self = @This();
        const Result = if (include_measure) MeasuredUpdate else Update;

        points: CodepointIterator,
        previous: ?u21 = null,
        state: if (include_measure) grapheme.TableState else segmentation.stream.GraphemeState = if (include_measure) .{ .id = 0 } else .{},
        measure: if (include_measure) grapheme.PresentationMeasure else void = if (include_measure) .{} else {},
        exhausted: bool = false,

        /// Select measurement before calling next(). Copies share the Reader;
        /// use only the returned iterator. Selecting it mid-cluster is invalid.
        pub fn measured(self: Self) Iterator(CodepointIterator, next_decoded, true) {
            if (include_measure) return self;
            if (self.previous != null or self.exhausted)
                @panic("select Reader grapheme measurement before iteration starts");
            return .{ .points = self.points };
        }

        pub inline fn next(self: *Self) CodepointIterator.Error!?Result {
            if (self.exhausted) return null;

            const maybe_decoded = try next_decoded(&self.points);
            if (maybe_decoded) |decoded| {
                const point = decoded.point;
                const starts_new = if (include_measure) blk: {
                    const token = decoded_token.fromCodepoint(0, 0, point.value);
                    const category = grapheme.categoryOf(token);
                    const boundary = if (self.previous != null) self.state.step(category) else first: {
                        self.state = .init(category);
                        break :first true;
                    };
                    if (boundary) self.measure = .{};
                    self.measure.addBounded(token);
                    break :blk boundary;
                } else if (self.previous) |previous|
                    segmentation.stream.graphemeBreak(previous, point.value, &self.state)
                else
                    true;
                self.previous = point.value;
                var result: Result = .{
                    ._bytes = decoded.raw,
                    ._len = decoded.len,
                    .starts_new = starts_new,
                    .is_final = false,
                };
                if (include_measure) self.setMeasure(&result);
                return result;
            }

            self.exhausted = true;
            if (self.previous == null) return null;
            var result: Result = .{
                .starts_new = false,
                .is_final = true,
            };
            if (include_measure) self.setMeasure(&result);
            return result;
        }

        inline fn setMeasure(self: *const Self, result: *MeasuredUpdate) void {
            const columns = self.measure.finish();
            result.columns = @intCast(grapheme.displayColumns(columns));
            result.renderable = grapheme.isRenderable(columns);
        }
    };
}
