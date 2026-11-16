//! The `File` store model and its TDLib payload.

const std = @import("std");

const common = @import("common.zig");

const Allocator = std.mem.Allocator;

pub const ParseError = common.ParseError;

/// A file known to TDLib; local fields are filled by `updateFile`.
pub const File = struct {
    /// TDLib file ids are `i32`.
    id: i32,
    size: ?i64,
    local_path: ?[]u8,
    is_downloading_completed: bool,

    allocator: Allocator,

    pub fn deinit(self: *File) void {
        if (self.local_path) |value| self.allocator.free(value);
        self.* = undefined;
    }

    /// Parses the JSON of a single `file` object. The caller owns the result.
    pub fn parse(allocator: Allocator, json: []const u8) ParseError!File {
        var parsed = try std.json.parseFromSlice(
            FilePayload,
            allocator,
            json,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();
        const payload = parsed.value;

        var file: File = .{
            .allocator = allocator,
            .id = payload.id,
            .size = payload.size,
            .local_path = null,
            .is_downloading_completed = false,
        };
        errdefer file.deinit();
        if (payload.local) |local| {
            file.local_path = try common.dupeString(allocator, if (local.path.len > 0) local.path else null);
            file.is_downloading_completed = local.is_downloading_completed;
        }
        return file;
    }
};

const FilePayload = struct {
    id: i32 = 0,
    size: ?i64 = null,
    local: ?LocalFilePayload = null,
};

const LocalFilePayload = struct {
    path: []const u8 = "",
    is_downloading_completed: bool = false,
};

test "file parses size and local path" {
    var file = try File.parse(
        std.testing.allocator,
        "{\"@type\":\"file\",\"id\":5,\"size\":1024,\"local\":{\"@type\":\"localFile\",\"path\":\"/tmp/pic.jpg\",\"is_downloading_completed\":true}}",
    );
    defer file.deinit();

    try std.testing.expectEqual(@as(i32, 5), file.id);
    try std.testing.expectEqual(@as(?i64, 1024), file.size);
    try std.testing.expectEqualStrings("/tmp/pic.jpg", file.local_path.?);
    try std.testing.expect(file.is_downloading_completed);
}

test "file without local part stays empty" {
    var file = try File.parse(
        std.testing.allocator,
        "{\"@type\":\"file\",\"id\":6,\"size\":null}",
    );
    defer file.deinit();

    try std.testing.expectEqual(@as(?i64, null), file.size);
    try std.testing.expectEqual(@as(?[]u8, null), file.local_path);
    try std.testing.expect(!file.is_downloading_completed);
}
