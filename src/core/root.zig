//! ZiGram core: Telegram logic with no GUI or platform dependencies.

const std = @import("std");

pub const td = @import("td/root.zig");
pub const request = @import("request.zig");
pub const auth = @import("auth/root.zig");
pub const store = @import("store/root.zig");
pub const updates = @import("updates.zig");
pub const chats = @import("chats.zig");
pub const files = @import("files.zig");

/// Human-readable version of the ZiGram core.
pub const version = "0.0.0";

test "core version is set" {
    try std.testing.expect(version.len > 0);
}

test {
    _ = @import("td/root.zig");
    _ = @import("request.zig");
    _ = @import("auth/root.zig");
    _ = @import("store/root.zig");
    _ = @import("updates.zig");
    _ = @import("chats.zig");
    _ = @import("files.zig");
}
