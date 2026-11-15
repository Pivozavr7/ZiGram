//! ZiGram core: Telegram logic with no GUI or platform dependencies.

const std = @import("std");

pub const td = @import("td.zig");

/// Human-readable version of the ZiGram core.
pub const version = "0.0.0";

test "core version is set" {
    try std.testing.expect(version.len > 0);
}

test {
    _ = @import("td.zig");
}
