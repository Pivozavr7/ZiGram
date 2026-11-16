//! Chat requests and response parsing: the chat list, chat metadata, history
//! and outgoing messages.
//!
//! This file never calls TDLib itself; the caller forwards built request
//! JSON through `td.Client.send`.

const std = @import("std");

const request = @import("request.zig");
const store = @import("store/root.zig");

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

/// Builds `getChatHistory` JSON. `from_message_id` of 0 means the newest
/// message; negative values walk backwards through the history.
pub fn getChatHistoryRequest(
    allocator: Allocator,
    chat_id: i64,
    from_message_id: i64,
    limit: i64,
) RequestError![]u8 {
    assert(limit > 0);

    return request.build(allocator, "getChatHistory", &.{
        .{ .name = "chat_id", .value = .{ .int = chat_id } },
        .{ .name = "from_message_id", .value = .{ .int = from_message_id } },
        .{ .name = "limit", .value = .{ .int = limit } },
        .{ .name = "only_local", .value = .{ .boolean = false } },
    });
}

/// Builds `sendMessage` JSON. The text is escaped, so any text can be sent.
pub fn sendMessageRequest(
    allocator: Allocator,
    chat_id: i64,
    text: []const u8,
) RequestError![]u8 {
    assert(text.len > 0);

    var aw: std.Io.Writer.Allocating = try .initCapacity(allocator, 128 + text.len);
    errdefer aw.deinit();
    const writer = &aw.writer;

    try writer.writeAll("{\"@type\":\"sendMessage\",\"chat_id\":");
    try writer.print("{d}", .{chat_id});
    try writer.writeAll(",\"input_message_content\":{\"@type\":\"inputMessageText\",\"text\":{\"@type\":\"formattedText\",\"text\":");
    try request.writeJsonString(writer, text);
    try writer.writeAll("}}}");

    return aw.toOwnedSlice();
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

/// A list of messages from a `messages` response.
pub const MessageList = struct {
    allocator: Allocator,
    items: []store.Message,

    pub fn deinit(self: *MessageList) void {
        for (self.items) |*message| message.deinit();
        self.allocator.free(self.items);
        self.* = undefined;
    }
};

/// Parses a `messages` response. Returns null when the response is of
/// another type.
pub fn parseMessages(
    allocator: Allocator,
    response_json: []const u8,
) ParseError!?MessageList {
    const Response = struct {
        @"@type": []const u8,
        messages: ?[]store.MessagePayload = null,
    };

    var parsed = try std.json.parseFromSlice(
        Response,
        allocator,
        response_json,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    if (!std.mem.eql(u8, parsed.value.@"@type", "messages")) {
        return null;
    }
    const payloads = parsed.value.messages orelse &[_]store.MessagePayload{};

    const items = try allocator.alloc(store.Message, payloads.len);
    errdefer allocator.free(items);
    for (payloads, items) |payload, *item| {
        item.* = try store.messageFromPayload(allocator, payload);
    }

    return .{ .allocator = allocator, .items = items };
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

test "history request is encoded" {
    const json = try getChatHistoryRequest(std.testing.allocator, 1001, 0, 30);
    defer std.testing.allocator.free(json);

    try std.testing.expectEqualStrings(
        "{\"@type\":\"getChatHistory\",\"chat_id\":1001,\"from_message_id\":0,\"limit\":30,\"only_local\":false}",
        json,
    );
}

test "send message request escapes the text" {
    const json = try sendMessageRequest(std.testing.allocator, 1001, "hi \"there\"\n");
    defer std.testing.allocator.free(json);

    try std.testing.expectEqualStrings(
        "{\"@type\":\"sendMessage\",\"chat_id\":1001,\"input_message_content\":{\"@type\":\"inputMessageText\",\"text\":{\"@type\":\"formattedText\",\"text\":\"hi \\\"there\\\"\\n\"}}}",
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

test "messages response is parsed" {
    var list = (try parseMessages(
        std.testing.allocator,
        "{\"@type\":\"messages\",\"messages\":[{\"@type\":\"message\",\"id\":1,\"chat_id\":10,\"content\":{\"@type\":\"messageText\",\"text\":{\"@type\":\"formattedText\",\"text\":\"hello\"}}}],\"@extra\":3}",
    )) orelse return error.TestUnexpectedResult;
    defer list.deinit();

    try std.testing.expectEqual(@as(usize, 1), list.items.len);
    try std.testing.expectEqualStrings("hello", list.items[0].content.text);
}

test "responses of other types are ignored" {
    const ids = try parseChatIds(std.testing.allocator, "{\"@type\":\"ok\"}");
    try std.testing.expectEqual(@as(?ChatIds, null), ids);

    const messages = try parseMessages(std.testing.allocator, "{\"@type\":\"ok\"}");
    try std.testing.expectEqual(@as(?MessageList, null), messages);
}
