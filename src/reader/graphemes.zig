//! Incremental grapheme bytes and boundaries over strict Reader codepoints.
const segmentation = @import("segmentation");

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

pub fn Iterator(comptime CodepointIterator: type, comptime next_decoded: anytype) type {
    return struct {
        points: CodepointIterator,
        previous: ?u21 = null,
        state: segmentation.stream.GraphemeState = .{},
        exhausted: bool = false,

        pub inline fn next(self: *@This()) CodepointIterator.Error!?Update {
            if (self.exhausted) return null;

            const maybe_decoded = try next_decoded(&self.points);
            if (maybe_decoded) |decoded| {
                const point = decoded.point;
                const starts_new = if (self.previous) |previous|
                    segmentation.stream.graphemeBreak(previous, point.value, &self.state)
                else
                    true;
                self.previous = point.value;
                return .{
                    ._bytes = decoded.raw,
                    ._len = decoded.len,
                    .starts_new = starts_new,
                    .is_final = false,
                };
            }

            self.exhausted = true;
            if (self.previous == null) return null;
            return .{
                .starts_new = false,
                .is_final = true,
            };
        }
    };
}
