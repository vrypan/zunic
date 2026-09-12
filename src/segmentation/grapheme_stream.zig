const grapheme = @import("grapheme.zig");

/// Incremental default UAX #29 grapheme state. Initialize with `.{};` copying
/// the value creates a checkpoint suitable for speculative appends.
pub const GraphemeState = struct {
    // Stored as plain data so the public checkpoint type does not expose the
    // internal table-state type or make its representation part of the API.
    _storage: [2]u8 = .{ 0, 0 },
};

/// Report the boundary between `previous` and `current` and advance `state`.
///
/// The first call seeds the state from `previous`. Later calls pass the last
/// `current` as `previous`; it is already represented by the state and is not
/// consumed twice. A boundary automatically resets the machine to the new
/// cluster. Values above U+10FFFF form independent boundaries and clear the
/// carried context. Surrogate code points use the tables' default `Other`
/// classification. Controls retain the standard UAX #29 behavior.
pub fn graphemeBreak(previous: u21, current: u21, state: *GraphemeState) bool {
    const previous_valid = previous <= 0x10ffff;
    const current_valid = current <= 0x10ffff;
    if (!current_valid) {
        state.* = .{};
        return true;
    }
    const current_category = grapheme.categoryForCodepoint(current);
    if (!previous_valid) {
        const machine = grapheme.TableState.init(current_category);
        state._storage = .{ machine.id, 1 };
        return true;
    }
    if (state._storage[1] == 0) {
        const machine = grapheme.TableState.init(grapheme.categoryForCodepoint(previous));
        state._storage = .{ machine.id, 1 };
    }
    var machine: grapheme.TableState = .{ .id = state._storage[0] };
    const boundary = machine.step(current_category);
    state._storage[0] = machine.id;
    return boundary;
}
