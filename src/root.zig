//! Allocation-free Unicode primitives for Zig terminal applications.
//!
//! Open a view over borrowed bytes and ask it questions:
//!
//! ```zig
//! const view = zunic.text(bytes);
//! const w = view.width();
//! var it = (try view.wrap(.{ .max_columns = 80 })).iterator();
//! ```
//!
//! Byte spans and terminal-column policy form the package's public boundary.
//! Nothing allocates, and every span indexes the slice the view was opened on.
//!
//! `text` reads bytes as plain text. **Strip ANSI escape sequences before
//! using it** -- it measures them as ordinary characters, so styled input
//! reports the wrong width and can be broken mid-sequence. A `terminal` view
//! that recognises them may follow.
pub const utf8 = @import("utf8.zig");
const text_view = @import("text.zig");
const wrap_engine = @import("wrap.zig");
pub const line_break = @import("line_break.zig");

pub const ByteOffset = text_view.ByteOffset;
pub const Column = text_view.Column;
pub const Span = text_view.Span;
pub const MeasuredSpan = text_view.MeasuredSpan;
pub const Line = text_view.Line;
pub const WrapOptions = wrap_engine.Options;
pub const Overflow = wrap_engine.Overflow;
pub const Wrapped = text_view.Wrapped;
pub const Text = text_view.Text;
pub const Terminators = text_view.Terminators;
pub const TerminatorIterator = text_view.TerminatorIterator;
pub const Graphemes = text_view.Graphemes;
pub const MeasuredGraphemes = text_view.MeasuredGraphemes;

/// Open a text view. Borrowed and zero-cost: no scanning happens until a
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
