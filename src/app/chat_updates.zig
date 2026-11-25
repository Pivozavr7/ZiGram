//! Dispatching TDLib events and their answers to the application state.

const std = @import("std");

const zigram = @import("zigram");

const auth = zigram.auth;
const chats = zigram.chats;
const store = zigram.store;
const updates = zigram.updates;

const commands = @import("commands.zig");
const log = @import("log.zig");
const state = @import("state.zig");

/// Runs a core event parser; an event that fails to parse is logged and
/// dropped instead of failing the frame. Out-of-memory still propagates.
pub fn parseTolerantly(
    comptime EventUpdate: type,
    allocator: std.mem.Allocator,
    logger: log.Logger,
    event_json: []const u8,
) !?EventUpdate {
    return EventUpdate.parse(allocator, event_json) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {
            logger.unparsable(err);
            return null;
        },
    };
}

/// Applies an `update*` event to the chat list and the histories.
pub fn applyUpdate(app_state: *state.State, event: updates.Event) !void {
    switch (event) {
        .new_chat => |chat| {
            try app_state.upsertChat(chat.id, chat.title, chat.unread_count, chat.order);
        },
        .chat_last_message => |payload| {
            if (payload.last_message) |message| {
                try app_state.setPreview(payload.chat_id, messageText(&message));
            }
            app_state.setOrder(payload.chat_id, payload.order);
        },
        .chat_read_inbox => |payload| {
            app_state.setUnread(payload.chat_id, payload.unread_count);
        },
        .new_message => |message| {
            try app_state.appendMessage(
                message.id,
                message.chat_id,
                message.is_outgoing,
                messageText(&message),
                message.date,
            );
        },
        .other => {},
    }
}

/// Applies the answer of TDLib to the chat list and the histories.
pub fn applyResponse(
    app_state: *state.State,
    sender: *commands.Commands,
    request: commands.Request,
    response_json: []const u8,
) !void {
    switch (request.kind) {
        .load_chats => {
            var ids = (try chats.parseChatIds(sender.allocator, response_json)) orelse return;
            defer ids.deinit();
            for (ids.ids) |chat_id| {
                try sender.loadChat(chat_id);
            }
        },
        .get_chat => {
            var chat = try store.Chat.parse(sender.allocator, response_json);
            defer chat.deinit();
            try app_state.upsertChat(chat.id, chat.title, chat.unread_count, chat.order);
        },
        .history => {
            var list = (try chats.parseMessages(sender.allocator, response_json)) orelse return;
            defer list.deinit();
            for (list.items) |*message| {
                try app_state.appendMessage(
                    message.id,
                    message.chat_id,
                    message.is_outgoing,
                    messageText(message),
                    message.date,
                );
            }
        },
        .send_message => {},
    }
}

/// The text of a message; non-text contents report their TDLib type name.
fn messageText(message: *const store.Message) []const u8 {
    return switch (message.content) {
        .text => |text| text,
        .other => |name| name,
        .unknown => "",
    };
}

test "read inbox and list order updates are applied to the state" {
    var app_state = state.State.init(std.testing.allocator);
    defer app_state.deinit();
    try app_state.upsertChat(1001, "Alice", 0, 0);

    try applyUpdate(&app_state, .{ .chat_read_inbox = .{ .chat_id = 1001, .unread_count = 4 } });
    try std.testing.expectEqual(@as(u32, 4), app_state.chats.items[0].unread_count);

    try applyUpdate(&app_state, .{ .chat_last_message = .{
        .chat_id = 1001,
        .last_message = null,
        .order = 500,
    } });
    try std.testing.expectEqual(@as(i64, 500), app_state.chats.items[0].order);
}
