//! Message requests and response parsing: the history and outgoing
//! messages.
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
/// A `reply_to_message_id` of 0 sends a message without a reply.
pub fn sendMessageRequest(
    allocator: Allocator,
    chat_id: i64,
    reply_to_message_id: i64,
    text: []const u8,
) RequestError![]u8 {
    assert(text.len > 0);

    var aw: std.Io.Writer.Allocating = try .initCapacity(allocator, 160 + text.len);
    errdefer aw.deinit();
    const writer = &aw.writer;

    try writer.writeAll("{\"@type\":\"sendMessage\",\"chat_id\":");
    try writer.print("{d}", .{chat_id});
    if (reply_to_message_id != 0) {
        try writer.writeAll(",\"reply_to_message_id\":");
        try writer.print("{d}", .{reply_to_message_id});
    }
    try writer.writeAll(",\"input_message_content\":{\"@type\":\"inputMessageText\",\"text\":{\"@type\":\"formattedText\",\"text\":");
    try request.writeJsonString(writer, text);
    try writer.writeAll("}}}");

    return aw.toOwnedSlice();
}

/// Builds `editMessageText` JSON: replaces the text of a sent message.
/// The text is escaped, so any text can be sent.
pub fn editMessageTextRequest(
    allocator: Allocator,
    chat_id: i64,
    message_id: i64,
    text: []const u8,
) RequestError![]u8 {
    assert(text.len > 0);

    var aw: std.Io.Writer.Allocating = try .initCapacity(allocator, 160 + text.len);
    errdefer aw.deinit();
    const writer = &aw.writer;

    try writer.writeAll("{\"@type\":\"editMessageText\",\"chat_id\":");
    try writer.print("{d}", .{chat_id});
    try writer.writeAll(",\"message_id\":");
    try writer.print("{d}", .{message_id});
    try writer.writeAll(",\"input_message_content\":{\"@type\":\"inputMessageText\",\"text\":{\"@type\":\"formattedText\",\"text\":");
    try request.writeJsonString(writer, text);
    try writer.writeAll("}}}");

    return aw.toOwnedSlice();
}

/// Builds `deleteMessages` JSON. `revoke` also deletes the messages on
/// the receiving side, when the chat allows it.
pub fn deleteMessagesRequest(
    allocator: Allocator,
    chat_id: i64,
    message_ids: []const i64,
    revoke: bool,
) RequestError![]u8 {
    assert(message_ids.len > 0);

    var aw: std.Io.Writer.Allocating = try .initCapacity(allocator, 128 + message_ids.len * 12);
    errdefer aw.deinit();
    const writer = &aw.writer;

    try writer.writeAll("{\"@type\":\"deleteMessages\",\"chat_id\":");
    try writer.print("{d}", .{chat_id});
    try writer.writeAll(",\"message_ids\":[");
    for (message_ids, 0..) |message_id, index| {
        if (index > 0) try writer.writeAll(",");
        try writer.print("{d}", .{message_id});
    }
    try writer.writeAll("],\"revoke\":");
    try writer.writeAll(if (revoke) "true" else "false");
    try writer.writeAll("}");

    return aw.toOwnedSlice();
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

test "history request is encoded" {
    const json = try getChatHistoryRequest(std.testing.allocator, 1001, 0, 30);
    defer std.testing.allocator.free(json);

    try std.testing.expectEqualStrings(
        "{\"@type\":\"getChatHistory\",\"chat_id\":1001,\"from_message_id\":0,\"limit\":30,\"only_local\":false}",
        json,
    );
}

test "send message request escapes the text" {
    const json = try sendMessageRequest(std.testing.allocator, 1001, 0, "hi \"there\"\n");
    defer std.testing.allocator.free(json);

    try std.testing.expectEqualStrings(
        "{\"@type\":\"sendMessage\",\"chat_id\":1001,\"input_message_content\":{\"@type\":\"inputMessageText\",\"text\":{\"@type\":\"formattedText\",\"text\":\"hi \\\"there\\\"\\n\"}}}",
        json,
    );
}

test "send message request encodes the reply" {
    const json = try sendMessageRequest(std.testing.allocator, 1001, 10, "hi");
    defer std.testing.allocator.free(json);

    try std.testing.expectEqualStrings(
        "{\"@type\":\"sendMessage\",\"chat_id\":1001,\"reply_to_message_id\":10,\"input_message_content\":{\"@type\":\"inputMessageText\",\"text\":{\"@type\":\"formattedText\",\"text\":\"hi\"}}}",
        json,
    );
}

test "edit message request escapes the text" {
    const json = try editMessageTextRequest(std.testing.allocator, 1001, 10, "new \"text\"");
    defer std.testing.allocator.free(json);

    try std.testing.expectEqualStrings(
        "{\"@type\":\"editMessageText\",\"chat_id\":1001,\"message_id\":10,\"input_message_content\":{\"@type\":\"inputMessageText\",\"text\":{\"@type\":\"formattedText\",\"text\":\"new \\\"text\\\"\"}}}",
        json,
    );
}

test "delete messages request encodes the ids" {
    const json = try deleteMessagesRequest(std.testing.allocator, 1001, &.{ 10, 11 }, true);
    defer std.testing.allocator.free(json);

    try std.testing.expectEqualStrings(
        "{\"@type\":\"deleteMessages\",\"chat_id\":1001,\"message_ids\":[10,11],\"revoke\":true}",
        json,
    );
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
    const messages = try parseMessages(std.testing.allocator, "{\"@type\":\"ok\"}");
    try std.testing.expectEqual(@as(?MessageList, null), messages);
}
