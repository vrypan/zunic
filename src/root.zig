//! Small, allocation-free Unicode primitives used by zooi.
//!
//! The module deliberately has no dependency on the rest of zooi. Byte spans
//! and terminal-column policy are its public boundary, which lets consumers
//! extract this directory into a separate module later.
pub const utf8 = @import("utf8.zig");
pub const grapheme = @import("grapheme.zig");
pub const width = @import("width.zig");
pub const line_break = @import("line_break.zig");
