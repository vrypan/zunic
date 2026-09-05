//! Line-break opportunities exposed to wrapping.
//!
//! Mandatory Unicode line separators are reported directly. Optional breaks
//! currently cover spaces and zero-width spaces; the property tables in this
//! component are ready for the complete context-sensitive UAX #14 state
//! machine, which is deliberately kept out until its full conformance suite
//! passes.
pub const Opportunity = enum { prohibited, allowed, mandatory };

pub fn after(cluster: []const u8) Opportunity {
    if (cluster.len == 0) return .prohibited;
    if (cluster[0] == '\n' or cluster[0] == '\r') return .mandatory;
    if (cluster[cluster.len - 1] == ' ' or cluster[cluster.len - 1] == '\t') return .allowed;
    return .prohibited;
}
