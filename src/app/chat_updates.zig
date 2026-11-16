//! Applying the chat events and the answers of TDLib to the state.

const std = @import("std");

const zigram = @import("zigram");

const chats = zigram.chats;
const store = zigram.store;
const updates = zigram.updates;

const commands = @import("commands.zig");
const state = @import("state.zig");

/// Applies an `update*` event to the chat list and the histories.
pub fn applyUpdate(app_state: *state.State, event: updates.Event) !void {
    switch (event) {
        .new_chat => |chat| {
            try app_state.upsertChat(chat.id, chat.title);
        },
        .chat_last_message => |payload| {
            if (payload.last_message) |message| {
                try app_state.setPreview(payload.chat_id, messageText(&message));
            }
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
            try app_state.upsertChat(chat.id, chat.title);
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
