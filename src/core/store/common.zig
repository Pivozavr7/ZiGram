//! Shared helpers of the store models.

const std = @import("std");

const Allocator = std.mem.Allocator;

pub const ParseError = std.json.ParseError(std.json.Scanner) || Allocator.Error;

/// Duplicates an optional string into an owned copy.
pub fn dupeString(allocator: Allocator, string: ?[]const u8) Allocator.Error!?[]u8 {
    const value = string orelse return null;
    return try allocator.dupe(u8, value);
}
