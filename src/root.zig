//! Allocation-free Unicode primitives for Zig terminal applications.
//!
//! Byte spans and terminal-column policy form the package's public boundary.
pub const utf8 = @import("utf8.zig");
pub const scalar = @import("scalar.zig");
pub const grapheme = @import("grapheme.zig");
pub const width = @import("width.zig");
pub const line_break = @import("line_break.zig");
pub const wrap = @import("wrap.zig");
pub const build_options = @import("build_options");
