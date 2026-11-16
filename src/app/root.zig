//! ZiGram application state: chat list, message history and selection.
//!
//! This layer knows nothing about GUI or SDL; the UI only reads the state and
//! sends commands.

pub const state = @import("state.zig");

test {
    _ = @import("state.zig");
}
