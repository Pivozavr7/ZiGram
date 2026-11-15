//! ZiGram core: Telegram logic with no GUI or platform dependencies.

const std = @import("std");

/// Human-readable version of the ZiGram core.
pub const version = "0.0.0";

test "core version is set" {
    try std.testing.expect(version.len > 0);
}
