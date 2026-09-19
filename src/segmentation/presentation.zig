//! Presentation-aware terminal measurement, kept out of ordinary slice scans.
const decoded_token = @import("encoding").decoded_token;
const terminal = @import("tables").terminal_properties;

pub const Measure = struct {
    // Commit a scalar's width only after seeing its immediate successor. This
    // lets VS15 narrow it even when preceding widths have already saturated.
    columns: usize = 0,
    pending_width: u2 = 0,
    previous: ?u21 = null,
    has_pictograph: bool = false,
    has_ri: bool = false,

    pub fn addBounded(self: *Measure, token: decoded_token.Token) void {
        if (token.codepoint) |cp| {
            if (cp == 0xfe0e or cp == 0xfe0f) {
                if (self.previous) |base| {
                    const properties = terminal.terminalProperties(base);
                    if (properties.emoji_variation_base) {
                        if (cp == 0xfe0f) {
                            self.pending_width = 2;
                            self.has_pictograph = true;
                        } else if (properties.emoji_presentation and !(base >= 0x1f200 and base <= 0x1f2ff)) {
                            self.pending_width = 1;
                        }
                    }
                }
            }
        }
        self.columns = @min(self.columns + self.pending_width, 3);
        self.previous = token.codepoint;
        self.pending_width = 0;
        const cp = token.codepoint orelse return;
        if (cp < 0x20 or cp == 0x7f) return;
        self.pending_width = token.cell_width;
        self.has_pictograph = self.has_pictograph or token.grapheme.extended_pictographic;
        self.has_ri = self.has_ri or token.grapheme.gcb == .regional_indicator;
    }

    pub fn finish(self: Measure) u3 {
        const columns = @min(self.columns + self.pending_width, 3);
        if (columns == 0) return 0;
        if (self.has_ri) return 2;
        if (self.has_pictograph) return @intCast(@min(columns, 2));
        // Three is the shared replacement sentinel, decoded by grapheme.
        return @intCast(columns);
    }
};
