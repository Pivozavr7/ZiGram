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
    /// Unread message count from TDLib.
    unread_count: u32,
    /// Sort order of the main chat list: bigger is newer, 0 when unknown.
    order: i64,
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
    /// File id of an attached photo; null for messages without one.
    photo_file_id: ?i32 = null,
};

/// Download state of one file, fed by `updateFile`.
pub const FileProgress = struct {
    file_id: i32,
    /// Bytes already downloaded.
    downloaded: i64 = 0,
    /// Total size, null until TDLib reports it.
    size: ?i64 = null,
    is_completed: bool = false,

    /// Fraction of the file that is downloaded, 0..=1.
    pub fn fraction(self: FileProgress) f32 {
        const size = self.size orelse return 0;
        if (size <= 0) return 0;
        const downloaded: f32 = @floatFromInt(self.downloaded);
        const total: f32 = @floatFromInt(size);
        return @min(downloaded / total, 1);
    }
};

/// Everything the UI reads: chats, histories and the current selection.
pub const State = struct {
    allocator: Allocator,
    chats: std.ArrayList(ChatEntry),
    messages: std.ArrayList(ChatMessages),
    /// Download progress by file id; only files the UI asked for appear.
    files: std.AutoHashMap(i32, FileProgress),
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
            .files = .init(allocator),
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
        self.files.deinit();

        self.* = undefined;
    }

    /// Stores the download progress of a file.
    pub fn setFileProgress(self: *State, progress: FileProgress) Allocator.Error!void {
        try self.files.put(progress.file_id, progress);
    }

    /// The download progress of a file; null while TDLib never reported it.
    pub fn fileProgress(self: *const State, file_id: i32) ?FileProgress {
        return self.files.get(file_id);
    }

    /// Inserts a chat or replaces the entry with the same id, then re-sorts
    /// the list by the main list order, newest first.
    pub fn upsertChat(
        self: *State,
        chat_id: i64,
        title: []const u8,
        unread_count: u32,
        order: i64,
    ) Allocator.Error!void {
        for (self.chats.items) |*entry| {
            if (entry.chat_id != chat_id) continue;
            const title_copy = try self.allocator.dupe(u8, title);
            self.allocator.free(entry.title);
            entry.title = title_copy;
            entry.unread_count = unread_count;
            entry.order = order;
            self.sortChats();
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
            .unread_count = unread_count,
            .order = order,
        });
        self.sortChats();
    }

    /// Sets the unread counter of a chat; unknown chats are ignored.
    pub fn setUnread(self: *State, chat_id: i64, unread_count: u32) void {
        for (self.chats.items) |*entry| {
            if (entry.chat_id != chat_id) continue;
            entry.unread_count = unread_count;
            return;
        }
    }

    /// Sets the main list order of a chat and re-sorts; unknown chats are
    /// ignored.
    pub fn setOrder(self: *State, chat_id: i64, order: i64) void {
        for (self.chats.items) |*entry| {
            if (entry.chat_id != chat_id) continue;
            entry.order = order;
            self.sortChats();
            return;
        }
    }

    /// Keeps the list ordered by the main list order, newest first; chats
    /// without an order keep their relative position.
    fn sortChats(self: *State) void {
        std.mem.sort(ChatEntry, self.chats.items, {}, lessByOrder);
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

    /// Appends a message to the history of its chat; `photo_file_id` is
    /// null for messages without a photo.
    pub fn appendMessage(
        self: *State,
        message_id: i64,
        chat_id: i64,
        is_outgoing: bool,
        text: []const u8,
        date: i32,
        photo_file_id: ?i32,
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
                .photo_file_id = photo_file_id,
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
            .photo_file_id = photo_file_id,
        });
        try self.messages.append(self.allocator, chat_messages);
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

/// Newest first: a bigger order comes first; chats without an order keep
/// their relative position behind the ordered ones.
fn lessByOrder(_: void, a: ChatEntry, b: ChatEntry) bool {
    if (a.order != b.order) return a.order > b.order;
    return a.chat_id < b.chat_id;
}

test {
    _ = @import("state_test.zig");
}
