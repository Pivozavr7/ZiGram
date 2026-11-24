//! Parsing of `update*` events into store models.
//!
//! This file never calls TDLib itself; the caller feeds raw `td_receive`
//! JSON here and matches responses by `@extra` before parsing the rest.
//!
//! The type name is parsed first and the payload only for the known event
//! kinds: other TDLib events may carry a field with the same name in an
//! entirely different shape (for example the `message` of an error response
//! is a string), and one malformed payload must not fail the whole frame.

const std = @import("std");

const store = @import("store/root.zig");

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
    /// Unknown `update*` type, or a known type whose payload has an
    /// unexpected shape. The owned name lets a caller log or ignore it.
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
        var name_parsed = try std.json.parseFromSlice(
            TypeName,
            allocator,
            event_json,
            .{ .ignore_unknown_fields = true },
        );
        defer name_parsed.deinit();

        const type_name = name_parsed.value.@"@type";
        if (!std.mem.startsWith(u8, type_name, "update")) {
            return null;
        }

        return parseEvent(allocator, type_name, event_json) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            // The payload has an unexpected shape; keep the event name and
            // let the caller ignore it instead of failing the whole frame.
            else => .{
                .allocator = allocator,
                .event = .{ .other = try allocator.dupe(u8, type_name) },
            },
        };
    }
};

/// Only the type name of an event; enough to route the payload parsing.
const TypeName = struct {
    @"@type": []const u8,
};

/// Parses the payload of a known `update*` kind. Unknown kinds become
/// `.other` events.
fn parseEvent(
    allocator: Allocator,
    type_name: []const u8,
    event_json: []const u8,
) ParseError!?Update {
    if (std.mem.eql(u8, type_name, "updateNewChat")) {
        return parseNewChat(allocator, event_json);
    }
    if (std.mem.eql(u8, type_name, "updateChatLastMessage")) {
        return parseChatLastMessage(allocator, event_json);
    }
    if (std.mem.eql(u8, type_name, "updateNewMessage")) {
        return parseNewMessage(allocator, event_json);
    }
    return .{
        .allocator = allocator,
        .event = .{ .other = try allocator.dupe(u8, type_name) },
    };
}

const NewChatPayload = struct {
    chat: ?store.ChatPayload = null,
};

fn parseNewChat(allocator: Allocator, event_json: []const u8) ParseError!?Update {
    var parsed = try std.json.parseFromSlice(
        NewChatPayload,
        allocator,
        event_json,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    const chat_payload = parsed.value.chat orelse return null;
    return .{
        .allocator = allocator,
        .event = .{ .new_chat = try store.chatFromPayload(allocator, chat_payload) },
    };
}

const ChatLastMessagePayload = struct {
    chat_id: i64 = 0,
    last_message: ?store.MessagePayload = null,
};

fn parseChatLastMessage(
    allocator: Allocator,
    event_json: []const u8,
) ParseError!?Update {
    var parsed = try std.json.parseFromSlice(
        ChatLastMessagePayload,
        allocator,
        event_json,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    var last_message: ?store.Message = null;
    if (parsed.value.last_message) |message_payload| {
        last_message = try store.messageFromPayload(allocator, message_payload);
    }
    return .{
        .allocator = allocator,
        .event = .{ .chat_last_message = .{
            .chat_id = parsed.value.chat_id,
            .last_message = last_message,
        } },
    };
}

const NewMessagePayload = struct {
    message: ?store.MessagePayload = null,
};

fn parseNewMessage(allocator: Allocator, event_json: []const u8) ParseError!?Update {
    var parsed = try std.json.parseFromSlice(
        NewMessagePayload,
        allocator,
        event_json,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    const message_payload = parsed.value.message orelse return null;
    return .{
        .allocator = allocator,
        .event = .{ .new_message = try store.messageFromPayload(allocator, message_payload) },
    };
}
