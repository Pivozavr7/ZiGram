//! Parsing of `update*` events into store models.
//!
//! This file never calls TDLib itself; the caller feeds raw `td_receive`
//! JSON here and matches responses by `@extra` before parsing the rest.

const std = @import("std");

const store = @import("store/root.zig");

const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

pub const ParseError = std.json.ParseError(std.json.Scanner) || Allocator.Error;

/// A parsed `update*` event. String payloads are owned copies; free
/// everything with `Update.deinit`.
pub const Event = union(enum) {
    /// `updateNewChat`: a chat was added to the chat list.
    new_chat: store.Chat,
    /// `updateChatLastMessage`: the chat list preview changed; the last
    /// message is null when it was removed.
    chat_last_message: struct {
        chat_id: i64,
        last_message: ?store.Message,
    },
    /// `updateNewMessage`: a new incoming or outgoing message.
    new_message: store.Message,
    /// Unknown `update*` type; the owned name lets a caller log or ignore it.
    other: []u8,
};

/// An owned update event.
pub const Update = struct {
    allocator: Allocator,
    event: Event,

    pub fn deinit(self: *Update) void {
        switch (self.event) {
            .new_chat => |*chat| chat.deinit(),
            .chat_last_message => |*payload| {
                if (payload.last_message) |*message| message.deinit();
            },
            .new_message => |*message| message.deinit(),
            .other => |name| self.allocator.free(name),
        }
        self.* = undefined;
    }

    /// Returns null when `event_json` is not an `update*` event, for example
    /// a response matched by `@extra`. Unknown fields are ignored on
    /// purpose: TDLib adds fields between versions.
    pub fn parse(
        allocator: Allocator,
        event_json: []const u8,
    ) ParseError!?Update {
        var parsed = try std.json.parseFromSlice(
            ParsedUpdate,
            allocator,
            event_json,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();

        const payload = parsed.value;
        const type_name = payload.@"@type";
        if (!std.mem.startsWith(u8, type_name, "update")) {
            return null;
        }

        if (std.mem.eql(u8, type_name, "updateNewChat")) {
            const chat_payload = payload.chat orelse return null;
            return .{
                .allocator = allocator,
                .event = .{
                    .new_chat = try store.chatFromPayload(allocator, chat_payload),
                },
            };
        }

        if (std.mem.eql(u8, type_name, "updateChatLastMessage")) {
            var last_message: ?store.Message = null;
            if (payload.last_message) |message_payload| {
                last_message = try store.messageFromPayload(allocator, message_payload);
            }
            return .{
                .allocator = allocator,
                .event = .{ .chat_last_message = .{
                    .chat_id = payload.chat_id,
                    .last_message = last_message,
                } },
            };
        }

        if (std.mem.eql(u8, type_name, "updateNewMessage")) {
            const message_payload = payload.message orelse return null;
            return .{
                .allocator = allocator,
                .event = .{
                    .new_message = try store.messageFromPayload(allocator, message_payload),
                },
            };
        }

        return .{
            .allocator = allocator,
            .event = .{ .other = try allocator.dupe(u8, type_name) },
        };
    }
};

const ParsedUpdate = struct {
    @"@type": []const u8,
    chat: ?store.ChatPayload = null,
    chat_id: i64 = 0,
    last_message: ?store.MessagePayload = null,
    message: ?store.MessagePayload = null,
};

test "updateNewChat parses into a chat" {
    var update = (try Update.parse(
        std.testing.allocator,
        "{\"@type\":\"updateNewChat\",\"chat\":{\"@type\":\"chat\",\"id\":1001,\"title\":\"Alice\",\"type\":{\"@type\":\"chatTypePrivate\",\"user_id\":42}},\"extra\":1}",
    )) orelse return error.TestUnexpectedResult;
    defer update.deinit();

    try std.testing.expect(update.event == .new_chat);
    try std.testing.expectEqual(@as(i64, 1001), update.event.new_chat.id);
    try std.testing.expectEqualStrings("Alice", update.event.new_chat.title);
}

test "updateChatLastMessage parses the preview message" {
    var update = (try Update.parse(
        std.testing.allocator,
        "{\"@type\":\"updateChatLastMessage\",\"chat_id\":1001,\"last_message\":{\"@type\":\"message\",\"id\":10,\"chat_id\":1001,\"date\":1700000000,\"content\":{\"@type\":\"messageText\",\"text\":{\"@type\":\"formattedText\",\"text\":\"hello\"}}},\"positions\":[]}",
    )) orelse return error.TestUnexpectedResult;
    defer update.deinit();

    try std.testing.expect(update.event == .chat_last_message);
    try std.testing.expectEqual(@as(i64, 1001), update.event.chat_last_message.chat_id);
    try std.testing.expectEqualStrings(
        "hello",
        update.event.chat_last_message.last_message.?.content.text,
    );
}

test "updateChatLastMessage allows a removed last message" {
    var update = (try Update.parse(
        std.testing.allocator,
        "{\"@type\":\"updateChatLastMessage\",\"chat_id\":1001,\"last_message\":null}",
    )) orelse return error.TestUnexpectedResult;
    defer update.deinit();

    try std.testing.expect(update.event == .chat_last_message);
    try std.testing.expectEqual(@as(?store.Message, null), update.event.chat_last_message.last_message);
}

test "updateNewMessage parses into a message" {
    var update = (try Update.parse(
        std.testing.allocator,
        "{\"@type\":\"updateNewMessage\",\"message\":{\"@type\":\"message\",\"id\":11,\"chat_id\":1001,\"sender_id\":{\"@type\":\"messageSenderUser\",\"user_id\":42},\"date\":1700000001,\"is_outgoing\":false,\"content\":{\"@type\":\"messageText\",\"text\":{\"@type\":\"formattedText\",\"text\":\"hi\"}}}}",
    )) orelse return error.TestUnexpectedResult;
    defer update.deinit();

    try std.testing.expect(update.event == .new_message);
    try std.testing.expectEqualStrings("hi", update.event.new_message.content.text);
    try std.testing.expectEqual(@as(i64, 42), update.event.new_message.sender.user);
}

test "parse keeps unknown update types" {
    var update = (try Update.parse(
        std.testing.allocator,
        "{\"@type\":\"updateSomethingBrandNew\",\"field\":1}",
    )) orelse return error.TestUnexpectedResult;
    defer update.deinit();

    try std.testing.expect(update.event == .other);
    try std.testing.expectEqualStrings("updateSomethingBrandNew", update.event.other);
}

test "parse returns null for responses" {
    const maybe = try Update.parse(
        std.testing.allocator,
        "{\"@type\":\"ok\",\"@extra\":1}",
    );

    try std.testing.expectEqual(@as(?Update, null), maybe);
}

test "parse returns null for malformed known updates" {
    const maybe = try Update.parse(
        std.testing.allocator,
        "{\"@type\":\"updateNewChat\"}",
    );

    try std.testing.expectEqual(@as(?Update, null), maybe);
}
