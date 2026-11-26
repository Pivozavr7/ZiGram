//! The `File` store model and its TDLib payload.

const std = @import("std");

const common = @import("common.zig");

const Allocator = std.mem.Allocator;

pub const ParseError = common.ParseError;

/// A file known to TDLib; local fields are filled by `updateFile`.
pub const File = struct {
    /// TDLib file ids are `i32`.
    id: i32,
    /// Total size in bytes; `size` falls back to `expected_size`, which is
    /// the only size TDLib reports while a remote file is still loading.
    size: ?i64,
    /// Bytes already downloaded; 0 while nothing has been downloaded.
    downloaded_prefix_size: i64,
    local_path: ?[]u8,
    is_downloading_completed: bool,

    allocator: Allocator,

    pub fn deinit(self: *File) void {
        if (self.local_path) |value| self.allocator.free(value);
        self.* = undefined;
    }

    /// Download progress in the range 0..=1; an unknown size reports 0.
    pub fn progress(self: *const File) f32 {
        const size = self.size orelse return 0;
        if (size <= 0) return 0;
        const downloaded: f32 = @floatFromInt(self.downloaded_prefix_size);
        const total: f32 = @floatFromInt(size);
        return @min(downloaded / total, 1);
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
        return fileFromPayload(allocator, parsed.value);
    }
};

pub const FilePayload = struct {
    id: i32 = 0,
    size: ?i64 = null,
    expected_size: ?i64 = null,
    local: ?LocalFilePayload = null,
};

const LocalFilePayload = struct {
    path: []const u8 = "",
    is_downloading_completed: bool = false,
    downloaded_prefix_size: i64 = 0,
};

/// Builds a `File` from an already-parsed payload. The caller owns the result.
pub fn fileFromPayload(allocator: Allocator, payload: FilePayload) Allocator.Error!File {
    var file: File = .{
        .allocator = allocator,
        .id = payload.id,
        .size = payload.size orelse payload.expected_size,
        .downloaded_prefix_size = 0,
        .local_path = null,
        .is_downloading_completed = false,
    };
    errdefer file.deinit();
    if (payload.local) |local| {
        file.local_path = try common.dupeString(allocator, if (local.path.len > 0) local.path else null);
        file.is_downloading_completed = local.is_downloading_completed;
        file.downloaded_prefix_size = local.downloaded_prefix_size;
    }
    return file;
}

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

test "expected size and download prefix report a progress" {
    var file = try File.parse(
        std.testing.allocator,
        "{\"@type\":\"file\",\"id\":7,\"expected_size\":400,\"local\":{\"@type\":\"localFile\",\"downloaded_prefix_size\":100}}",
    );
    defer file.deinit();

    try std.testing.expectEqual(@as(?i64, 400), file.size);
    try std.testing.expectEqual(@as(i64, 100), file.downloaded_prefix_size);
    try std.testing.expectEqual(@as(f32, 0.25), file.progress());
    try std.testing.expect(!file.is_downloading_completed);
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
