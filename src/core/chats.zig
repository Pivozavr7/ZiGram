//! Chat requests and response parsing: the chat list and chat metadata.
//!
//! This file never calls TDLib itself; the caller forwards built request
//! JSON through `td.Client.send`.

const std = @import("std");

const request = @import("request.zig");

const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

pub const RequestError = request.Error;

pub const ParseError = std.json.ParseError(std.json.Scanner) || Allocator.Error;

/// Builds `loadChats` JSON: asks TDLib for the main chat list.
pub fn loadChatsRequest(
    allocator: Allocator,
    limit: i64,
) RequestError![]u8 {
    assert(limit > 0);

    return request.build(allocator, "loadChats", &.{
        .{ .name = "chat_list", .value = .{ .json = "{\"@type\":\"chatListMain\"}" } },
        .{ .name = "limit", .value = .{ .int = limit } },
    });
}

/// Builds `getChat` JSON: asks TDLib for one chat by id.
pub fn getChatRequest(
    allocator: Allocator,
    chat_id: i64,
) RequestError![]u8 {
    return request.build(allocator, "getChat", &.{
        .{ .name = "chat_id", .value = .{ .int = chat_id } },
    });
}

/// The chat ids of a `chats` response.
pub const ChatIds = struct {
    allocator: Allocator,
    ids: []i64,

    pub fn deinit(self: *ChatIds) void {
        self.allocator.free(self.ids);
        self.* = undefined;
    }
};

/// Parses a `chats` response. Returns null when the response is of another
/// type.
pub fn parseChatIds(
    allocator: Allocator,
    response_json: []const u8,
) ParseError!?ChatIds {
    const Response = struct {
        @"@type": []const u8,
        chat_ids: ?[]i64 = null,
    };

    var parsed = try std.json.parseFromSlice(
        Response,
        allocator,
        response_json,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    if (!std.mem.eql(u8, parsed.value.@"@type", "chats")) {
        return null;
    }
    const ids = parsed.value.chat_ids orelse &[_]i64{};

    return .{ .allocator = allocator, .ids = try allocator.dupe(i64, ids) };
}

test "load chats request is encoded" {
    const json = try loadChatsRequest(std.testing.allocator, 50);
    defer std.testing.allocator.free(json);

    try std.testing.expectEqualStrings(
        "{\"@type\":\"loadChats\",\"chat_list\":{\"@type\":\"chatListMain\"},\"limit\":50}",
        json,
    );
}

test "get chat request is encoded" {
    const json = try getChatRequest(std.testing.allocator, 1001);
    defer std.testing.allocator.free(json);

    try std.testing.expectEqualStrings(
        "{\"@type\":\"getChat\",\"chat_id\":1001}",
        json,
    );
}

test "chat ids response is parsed" {
    var ids = (try parseChatIds(
        std.testing.allocator,
        "{\"@type\":\"chats\",\"chat_ids\":[10,20],\"@extra\":7}",
    )) orelse return error.TestUnexpectedResult;
    defer ids.deinit();

    try std.testing.expectEqual(@as(usize, 2), ids.ids.len);
    try std.testing.expectEqual(@as(i64, 10), ids.ids[0]);
    try std.testing.expectEqual(@as(i64, 20), ids.ids[1]);
}

test "responses of other types are ignored" {
    const ids = try parseChatIds(std.testing.allocator, "{\"@type\":\"ok\"}");
    try std.testing.expectEqual(@as(?ChatIds, null), ids);
}
