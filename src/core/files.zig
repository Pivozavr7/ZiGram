//! Requests for TDLib files.

const std = @import("std");

const request = @import("request.zig");

const Allocator = std.mem.Allocator;

/// Priority of an automatic download; TDLib accepts 1..=32.
const download_priority = 16;

/// Asks TDLib to download a file; the progress arrives as `updateFile`.
/// The caller owns the result.
pub fn downloadFileRequest(allocator: Allocator, file_id: i32) request.Error![]u8 {
    return request.build(allocator, "downloadFile", &.{
        .{ .name = "file_id", .value = .{ .int = file_id } },
        .{ .name = "priority", .value = .{ .int = download_priority } },
        .{ .name = "offset", .value = .{ .int = 0 } },
        .{ .name = "limit", .value = .{ .int = 0 } },
        .{ .name = "synchronous", .value = .{ .boolean = false } },
    });
}

test "downloadFile asks for the whole file" {
    const json = try downloadFileRequest(std.testing.allocator, 901);
    defer std.testing.allocator.free(json);

    try std.testing.expectEqualStrings(
        "{\"@type\":\"downloadFile\",\"file_id\":901,\"priority\":16,\"offset\":0,\"limit\":0,\"synchronous\":false}",
        json,
    );
}
