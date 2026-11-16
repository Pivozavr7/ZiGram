//! ZiGram application layer: session, state, commands and configuration.
//!
//! This layer knows nothing about GUI or SDL; the UI only reads the state and
//! sends commands.

pub const chat_updates = @import("chat_updates.zig");
pub const commands = @import("commands.zig");
pub const config = @import("config.zig");
pub const login = @import("login.zig");
pub const log = @import("log.zig");
pub const parameters = @import("parameters.zig");
pub const session = @import("session.zig");
pub const state = @import("state.zig");

test {
    _ = @import("chat_updates.zig");
    _ = @import("commands.zig");
    _ = @import("config.zig");
    _ = @import("login.zig");
    _ = @import("log.zig");
    _ = @import("parameters.zig");
    _ = @import("session.zig");
    _ = @import("state.zig");
}
