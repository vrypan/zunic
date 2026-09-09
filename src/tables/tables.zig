//! Generated Unicode tables. No logic and no dependencies: every other module
//! reads facts from here, and this one reads nothing.
//!
//! `properties` is deliberately shared rather than split per engine. Its
//! `Record` packs grapheme, width and line-break facts into one `u32` so a
//! scanner looks a scalar up once and answers all three questions from the
//! same entry; see `docs/architecture.md`. Splitting it would mean either
//! duplicating table data or paying a lookup per question.
//!
//! Regenerate with the scripts under `src/tools/`; never hand-edit.
pub const properties = @import("properties.zig");
pub const word = @import("word_properties.zig");
pub const normalization = @import("normalization_properties.zig");
pub const stream_safe = @import("stream_safe_properties.zig");
pub const line_break_machine_data = @import("line_break_machine_data.zig");
