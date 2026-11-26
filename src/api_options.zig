//! Parsing of the non-secret startup options the shell passes as JSON.

const std = @import("std");

const Allocator = std.mem.Allocator;

/// Non-secret startup options the shell may pass as JSON. Unknown fields are
/// ignored, so a newer shell stays compatible with an older core.
const StartOptions = struct {
    tdlib_path: ?[]const u8 = null,
    /// TDLib data directory; an empty one starts a fresh session. The
    /// credentials still come from `config.zon`.
    database_dir: ?[]const u8 = null,
};

/// Owned copies of the startup overrides.
pub const Overrides = struct {
    tdlib_path: ?[]u8 = null,
    database_dir: ?[]u8 = null,

    pub fn deinit(self: *Overrides, gpa: Allocator) void {
        if (self.tdlib_path) |path| gpa.free(path);
        if (self.database_dir) |dir| gpa.free(dir);
        self.* = undefined;
    }
};

/// Parses the non-secret JSON options; free with `Overrides.deinit`.
pub fn parseOverrides(gpa: Allocator, config_json: []const u8) !Overrides {
    if (config_json.len == 0) return .{};
    var parsed = std.json.parseFromSlice(StartOptions, gpa, config_json, .{
        .ignore_unknown_fields = true,
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.ConfigJsonInvalid,
    };
    defer parsed.deinit();

    var overrides: Overrides = .{};
    errdefer overrides.deinit(gpa);
    if (parsed.value.tdlib_path) |path| {
        overrides.tdlib_path = try gpa.dupe(u8, path);
    }
    if (parsed.value.database_dir) |dir| {
        overrides.database_dir = try gpa.dupe(u8, dir);
    }
    return overrides;
}

test "start options ignore unknown fields" {
    var overrides = try parseOverrides(
        std.testing.allocator,
        "{\"tdlib_path\":\"/tmp/libtdjson.so\",\"future_field\":true}",
    );
    defer overrides.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings(
        "/tmp/libtdjson.so",
        overrides.tdlib_path.?,
    );
}

test "start options carry the database directory" {
    var overrides = try parseOverrides(
        std.testing.allocator,
        "{\"database_dir\":\"/tmp/fresh\"}",
    );
    defer overrides.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("/tmp/fresh", overrides.database_dir.?);
    try std.testing.expectEqual(@as(?[]u8, null), overrides.tdlib_path);
}

test "an empty config json means no overrides" {
    var overrides = try parseOverrides(std.testing.allocator, "");
    defer overrides.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(?[]u8, null), overrides.tdlib_path);
    try std.testing.expectEqual(@as(?[]u8, null), overrides.database_dir);
}
