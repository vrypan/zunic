//! Generated Unicode tables. No logic and no dependencies: every other module
//! reads facts from here, and this one reads nothing.
//!
//! `grapheme` is the compact scalar table used by grapheme-only consumers.
//! `properties` keeps the wider fused record used by layout and line breaking,
//! where one lookup must answer grapheme, width, and line-break questions.
//!
//! Regenerate with the scripts under `src/tools/`; never hand-edit.
pub const properties = @import("properties.zig");
pub const grapheme = @import("grapheme_properties.zig");
pub const word = @import("word_properties.zig");
pub const normalization = @import("normalization_properties.zig");
pub const stream_safe = @import("stream_safe_properties.zig");
pub const line_break_machine_data = @import("line_break_machine_data.zig");
pub const general_category = @import("general_category.zig");
pub const terminal_properties = @import("terminal_properties.zig");
pub const case_folding = @import("case_folding.zig");
pub const simple_case_mappings = @import("simple_case_mappings.zig");
pub const numeric = @import("numeric_properties.zig");
