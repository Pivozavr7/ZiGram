//! Application state: the chat list, the message history and the selection.
//!
//! The state stores plain owned copies instead of the core models, so the
//! core can free its parsed objects as soon as they are applied.

const std = @import("std");

const Allocator = std.mem.Allocator;

/// One row of the chat list.
pub const ChatEntry = struct {
    chat_id: i64,
    /// Owned chat title; empty when TDLib has none yet.
    title: []u8,
    /// Owned preview of the last message.
    preview: []u8,
};

/// One message of a chat history.
pub const MessageEntry = struct {
    message_id: i64,
    chat_id: i64,
    is_outgoing: bool,
    /// Owned message text; empty for messages without text.
    text: []u8,
    /// Unix timestamp in seconds.
    date: i32,
};

/// Everything the UI reads: chats, histories and the current selection.
pub const State = struct {
    allocator: Allocator,
    chats: std.ArrayList(ChatEntry),
    messages: std.ArrayList(ChatMessages),
    selected_chat_id: ?i64 = null,

    /// Messages of one chat, oldest first.
    const ChatMessages = struct {
        chat_id: i64,
        items: std.ArrayList(MessageEntry),
    };

    pub fn init(allocator: Allocator) State {
        return .{
            .allocator = allocator,
            .chats = .empty,
            .messages = .empty,
        };
    }

    pub fn deinit(self: *State) void {
        for (self.chats.items) |*entry| {
            self.allocator.free(entry.title);
            self.allocator.free(entry.preview);
        }
        self.chats.deinit(self.allocator);

        for (self.messages.items) |*chat_messages| {
            for (chat_messages.items.items) |*message| {
                self.allocator.free(message.text);
            }
            chat_messages.items.deinit(self.allocator);
        }
        self.messages.deinit(self.allocator);

        self.* = undefined;
    }

    /// Inserts a chat or replaces the entry with the same id.
    pub fn upsertChat(self: *State, chat_id: i64, title: []const u8) Allocator.Error!void {
        for (self.chats.items) |*entry| {
            if (entry.chat_id != chat_id) continue;
            const title_copy = try self.allocator.dupe(u8, title);
            self.allocator.free(entry.title);
            entry.title = title_copy;
            return;
        }

        const title_copy = try self.allocator.dupe(u8, title);
        errdefer self.allocator.free(title_copy);
        const preview_copy = try self.allocator.dupe(u8, "");
        errdefer self.allocator.free(preview_copy);
        try self.chats.append(self.allocator, .{
            .chat_id = chat_id,
            .title = title_copy,
            .preview = preview_copy,
        });
    }

    /// Replaces the preview of a chat; unknown chats are ignored.
    pub fn setPreview(self: *State, chat_id: i64, preview: []const u8) Allocator.Error!void {
        for (self.chats.items) |*entry| {
            if (entry.chat_id != chat_id) continue;
            const preview_copy = try self.allocator.dupe(u8, preview);
            self.allocator.free(entry.preview);
            entry.preview = preview_copy;
            return;
        }
    }

    /// Appends a message to the history of its chat.
    pub fn appendMessage(
        self: *State,
        message_id: i64,
        chat_id: i64,
        is_outgoing: bool,
        text: []const u8,
        date: i32,
    ) Allocator.Error!void {
        const text_copy = try self.allocator.dupe(u8, text);
        errdefer self.allocator.free(text_copy);

        for (self.messages.items) |*chat_messages| {
            if (chat_messages.chat_id != chat_id) continue;
            try chat_messages.items.append(self.allocator, .{
                .message_id = message_id,
                .chat_id = chat_id,
                .is_outgoing = is_outgoing,
                .text = text_copy,
                .date = date,
            });
            return;
        }

        var chat_messages: ChatMessages = .{
            .chat_id = chat_id,
            .items = .empty,
        };
        errdefer {
            for (chat_messages.items.items) |*message| {
                self.allocator.free(message.text);
            }
            chat_messages.items.deinit(self.allocator);
        }
        try chat_messages.items.append(self.allocator, .{
            .message_id = message_id,
            .chat_id = chat_id,
            .is_outgoing = is_outgoing,
            .text = text_copy,
            .date = date,
        });
        try self.messages.append(self.allocator, chat_messages);
    }

    /// Replaces the text of a message in the history of its chat; unknown
    /// chats and messages are ignored.
    pub fn editMessageText(
        self: *State,
        chat_id: i64,
        message_id: i64,
        text: []const u8,
    ) Allocator.Error!void {
        for (self.messages.items) |*chat_messages| {
            if (chat_messages.chat_id != chat_id) continue;
            for (chat_messages.items.items) |*entry| {
                if (entry.message_id != message_id) continue;
                const text_copy = try self.allocator.dupe(u8, text);
                self.allocator.free(entry.text);
                entry.text = text_copy;
                return;
            }
            return;
        }
    }

    /// Messages of a chat, oldest first; empty for an unknown chat.
    pub fn messagesFor(self: *const State, chat_id: i64) []const MessageEntry {
        for (self.messages.items) |*chat_messages| {
            if (chat_messages.chat_id == chat_id) return chat_messages.items.items;
        }
        return &[_]MessageEntry{};
    }

    /// Selects a chat; reports whether the selection changed.
    pub fn selectChat(self: *State, chat_id: i64) bool {
        if (self.selected_chat_id) |current| {
            if (current == chat_id) return false;
        }
        self.selected_chat_id = chat_id;
        return true;
    }

    pub fn selectedChatId(self: *const State) ?i64 {
        return self.selected_chat_id;
    }
};

test "chats are inserted and updated" {
    var state = State.init(std.testing.allocator);
    defer state.deinit();

    try state.upsertChat(1, "Alice");
    try state.upsertChat(2, "Bob");
    try state.upsertChat(1, "Alice Updated");

    try std.testing.expectEqual(@as(usize, 2), state.chats.items.len);
    try std.testing.expectEqualStrings("Alice Updated", state.chats.items[0].title);
}

test "preview and messages are stored per chat" {
    var state = State.init(std.testing.allocator);
    defer state.deinit();

    try state.upsertChat(1, "Alice");
    try state.setPreview(1, "hi there");
    try state.appendMessage(10, 1, false, "hi there", 1700000000);
    try state.appendMessage(11, 2, true, "ignored", 1700000001);

    try std.testing.expectEqualStrings("hi there", state.chats.items[0].preview);
    try std.testing.expectEqual(@as(usize, 1), state.messagesFor(1).len);
    try std.testing.expectEqualStrings("hi there", state.messagesFor(1)[0].text);
    try std.testing.expectEqual(@as(usize, 1), state.messagesFor(2).len);
}

test "message text is replaced in place" {
    var state = State.init(std.testing.allocator);
    defer state.deinit();

    try state.upsertChat(1, "Alice");
    try state.appendMessage(10, 1, false, "hi there", 1700000000);
    try state.editMessageText(1, 10, "hi there (edited)");

    try std.testing.expectEqualStrings("hi there (edited)", state.messagesFor(1)[0].text);
}

test "selection reports changes" {
    var state = State.init(std.testing.allocator);
    defer state.deinit();

    try std.testing.expect(state.selectChat(5));
    try std.testing.expect(!state.selectChat(5));
    try std.testing.expectEqual(@as(?i64, 5), state.selectedChatId());
}
