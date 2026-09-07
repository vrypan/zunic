//! Allocation-free Unicode primitives for Zig terminal applications.
//!
//! Open a lens over borrowed bytes and ask it questions:
//!
//! ```zig
//! const view = zunic.text(bytes);
//! const w = view.width();
//! var it = try view.wrap(.{ .max_columns = 80 });
//! ```
//!
//! Byte spans and terminal-column policy form the package's public boundary.
//! Nothing allocates, and every span indexes the slice the lens was opened on.
//!
//! `text` reads bytes as plain text. **Strip ANSI escape sequences before
//! using it** -- it measures them as ordinary characters, so styled input
//! reports the wrong width and can be broken mid-sequence. A `terminal` lens
//! that recognises them may follow.
pub const utf8 = @import("utf8.zig");
const lens = @import("lens.zig");
const wrap_engine = @import("wrap.zig");
pub const line_break = @import("line_break.zig");

pub const ByteOffset = lens.ByteOffset;
pub const GraphemeIndex = lens.GraphemeIndex;
pub const Column = lens.Column;
pub const Span = lens.Span;
pub const MeasuredSpan = lens.MeasuredSpan;
pub const Line = lens.Line;
pub const WrapOptions = wrap_engine.Options;
pub const Overflow = wrap_engine.Overflow;
pub const Wrapped = lens.Wrapped;
pub const Text = lens.Text;
pub const Terminators = lens.Terminators;
pub const TerminatorIterator = lens.TerminatorIterator;
pub const Graphemes = lens.Graphemes(false);
pub const MeasuredGraphemes = lens.Graphemes(true);

/// Open a text lens. Borrowed and zero-cost: no scanning happens until a
/// question is asked.
pub fn text(bytes: []const u8) Text {
    return .{ .bytes = bytes };
}

/// Instrumented wrapping is retained solely for zunic's work-bound tests.
pub const testing = struct {
    pub const instrumentedIterator = wrap_engine.instrumentedIterator;
};

const std = @import("std");
pub const build_options = @import("build_options");
