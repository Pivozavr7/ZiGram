//! The `User` store model and its TDLib payload.

const std = @import("std");

const common = @import("common.zig");

const Allocator = std.mem.Allocator;

pub const ParseError = common.ParseError;

/// A Telegram user.
pub const User = struct {
    /// TDLib ids are int53; they fit into `i64`.
    id: i64,
    first_name: ?[]u8,
    last_name: ?[]u8,
    username: ?[]u8,
    is_bot: bool,

    allocator: Allocator,

    pub fn deinit(self: *User) void {
        if (self.first_name) |value| self.allocator.free(value);
        if (self.last_name) |value| self.allocator.free(value);
        if (self.username) |value| self.allocator.free(value);
        self.* = undefined;
    }

    /// Parses the JSON of a single `user` object. The caller owns the result.
    pub fn parse(allocator: Allocator, json: []const u8) ParseError!User {
        var parsed = try std.json.parseFromSlice(
            UserPayload,
            allocator,
            json,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();
        const payload = parsed.value;

        var user: User = .{
            .allocator = allocator,
            .id = payload.id,
            .first_name = null,
            .last_name = null,
            .username = null,
            .is_bot = payload.is_bot,
        };
        errdefer user.deinit();
        user.first_name = try common.dupeString(allocator, payload.first_name);
        user.last_name = try common.dupeString(allocator, payload.last_name);
        user.username = try common.dupeString(allocator, payload.username);
        return user;
    }
};

const UserPayload = struct {
    id: i64 = 0,
    first_name: ?[]const u8 = null,
    last_name: ?[]const u8 = null,
    username: ?[]const u8 = null,
    is_bot: bool = false,
};

test "user parses names and ignores unknown fields" {
    var user = try User.parse(
        std.testing.allocator,
        "{\"@type\":\"user\",\"id\":42,\"first_name\":\"Ada\",\"last_name\":\"Lovelace\",\"is_bot\":false,\"random_new_field\":[1,2]}",
    );
    defer user.deinit();

    try std.testing.expectEqual(@as(i64, 42), user.id);
    try std.testing.expectEqualStrings("Ada", user.first_name.?);
    try std.testing.expectEqualStrings("Lovelace", user.last_name.?);
    try std.testing.expectEqual(@as(?[]u8, null), user.username);
    try std.testing.expect(!user.is_bot);
}

test "user parses bot flag and username" {
    var user = try User.parse(
        std.testing.allocator,
        "{\"@type\":\"user\",\"id\":777,\"first_name\":\"Bot\",\"username\":\"bot_name\",\"is_bot\":true}",
    );
    defer user.deinit();

    try std.testing.expect(user.is_bot);
    try std.testing.expectEqualStrings("bot_name", user.username.?);
}
