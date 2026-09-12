const data = @import("tables").case_folding;

/// Allocation-free result of full default Unicode case folding.
pub const CaseFold = struct {
    codepoints: [3]u21,
    len: u2,

    /// Borrow the populated prefix. Keep this `CaseFold` value alive while
    /// using the returned slice.
    pub fn slice(self: *const CaseFold) []const u21 {
        return self.codepoints[0..self.len];
    }
};

/// Full default case fold for one code point. Statuses C and F from
/// CaseFolding.txt are used; Turkic alternatives are intentionally excluded.
pub fn fullCaseFold(cp: u21) CaseFold {
    if (cp >= 'A' and cp <= 'Z')
        return .{ .codepoints = .{ cp + ('a' - 'A'), 0, 0 }, .len = 1 };
    if (cp <= 0x10ffff) {
        const block = data.block_index[cp >> data.block_shift];
        const mapping_id = data.mapping_ids[
            (@as(usize, block) << data.block_shift) |
                (cp & ((@as(usize, 1) << data.block_shift) - 1))
        ];
        if (mapping_id != 0) {
            const mapping = data.mappings[mapping_id - 1];
            return .{ .codepoints = mapping.codepoints, .len = mapping.len };
        }
    }
    return .{ .codepoints = .{ cp, 0, 0 }, .len = 1 };
}
