//! The chat list, the conversation of the selected chat and the composer.

const std = @import("std");

const zigram_app = @import("zigram_app");

const gfx = @import("../gfx.zig");
const theme = @import("../theme/root.zig");
const widgets = @import("../widgets.zig");

const Session = zigram_app.session.Session;
const MessageEntry = zigram_app.state.MessageEntry;

const virtual_list = @import("../virtual_list.zig");

/// What the screen asks the frame loop to do.
pub const Outcome = enum { keep_running, quit };

/// The two-pane client view: chats on the left, conversation on the right.
pub const ChatList = struct {
    /// Buffer of the message composer.
    input: [4096]u8 = @splat(0),

    /// Measured bubble heights of the open chat, in message order; the
    /// list is virtualized, so only the visible slice is drawn.
    heights: std.ArrayList(f32) = .empty,
    /// What the height cache was measured for.
    cached_chat_id: i64 = 0,
    cached_count: usize = 0,
    cached_last_id: i64 = 0,
    cached_width: f32 = 0,
    /// Total height of the list in the previous frame.
    prev_total: f32 = 0,
    /// Set when the next frame has to scroll to the bottom.
    jump_to_bottom: bool = true,

    pub fn deinit(self: *ChatList, allocator: std.mem.Allocator) void {
        self.heights.deinit(allocator);
        self.* = undefined;
    }

    /// Draws the whole client view.
    pub fn draw(
        self: *ChatList,
        session: *Session,
        scratch: std.mem.Allocator,
    ) Outcome {
        const tokens = theme.current();

        const chats_shown = gfx.beginChild("Chats", tokens.panel_width, 0);
        if (chats_shown) self.drawChats(session, scratch);
        gfx.endChild();

        gfx.sameLine();

        const conversation_shown = gfx.beginChild("Conversation", 0, 0);
        var outcome: Outcome = .keep_running;
        if (conversation_shown) outcome = self.drawConversation(session, scratch);
        gfx.endChild();
        return outcome;
    }

    /// The pane with the chat list; the caller opens and closes the region.
    fn drawChats(self: *ChatList, session: *Session, scratch: std.mem.Allocator) void {
        _ = self;
        widgets.text("Chats");
        if (session.state.chats.items.len == 0) {
            widgets.disabled("no chats yet");
        }
        for (session.state.chats.items) |*entry| {
            const label = if (entry.unread_count > 0)
                scratch.printSentinel(
                    "{s}  {s}  ({d})",
                    .{ entry.title, entry.preview, entry.unread_count },
                    0,
                ) catch continue
            else
                scratch.printSentinel(
                    "{s}  {s}",
                    .{ entry.title, entry.preview },
                    0,
                ) catch continue;
            if (!gfx.selectable(label, session.state.selectedChatId() == entry.chat_id)) continue;
            if (session.state.selectChat(entry.chat_id)) {
                session.loadHistory(entry.chat_id) catch |err| {
                    session.reportError("loading the history", err);
                };
            }
        }
    }

    /// The pane with the header, the messages and the pinned composer.
    fn drawConversation(
        self: *ChatList,
        session: *Session,
        scratch: std.mem.Allocator,
    ) Outcome {
        const tokens = theme.current();
        drawHeader(session);

        // The composer row stays at the bottom: the messages get whatever
        // is left of the pane after the composer, the button and the
        // spacing around them.
        const composer =
            tokens.composer_height + gfx.frameHeight() + 2 * tokens.spacing.y;
        const messages_shown = gfx.beginChild("Messages", 0, -composer);
        if (messages_shown) self.drawMessages(session, scratch);
        gfx.endChild();

        _ = gfx.inputMultiline("Message", self.input[0..], tokens.composer_height);
        if (gfx.button("Send")) {
            self.send(session) catch |err| {
                session.reportError("sending the message", err);
            };
        }
        gfx.sameLine();
        if (gfx.button("Quit")) return .quit;
        return .keep_running;
    }

    /// The title of the open chat above the messages.
    fn drawHeader(session: *Session) void {
        const chat_id = session.state.selectedChatId() orelse {
            widgets.disabled("select a chat");
            return;
        };
        for (session.state.chats.items) |*entry| {
            if (entry.chat_id == chat_id) {
                widgets.text(entry.title);
                return;
            }
        }
    }

    fn drawMessages(self: *ChatList, session: *Session, scratch: std.mem.Allocator) void {
        const chat_id = session.state.selectedChatId() orelse return;
        const items = session.state.messagesFor(chat_id);
        self.measureHeights(session, scratch, items) catch return;

        const total = virtual_list.totalHeight(self.heights.items);
        const view_height = gfx.windowHeight();
        const scroll_y = gfx.scrollY();
        // A new chat, or a viewport that already follows the bottom, stays
        // at the bottom when the history grows.
        if (self.jump_to_bottom or scroll_y + view_height >= self.prev_total - 8) {
            gfx.setScrollY(total);
            self.jump_to_bottom = false;
        }
        self.prev_total = total;

        const range = virtual_list.visibleRange(self.heights.items, gfx.scrollY(), view_height);
        if (range.start == 0 and gfx.scrollY() <= 0) {
            self.loadOlder(session, chat_id);
        }

        gfx.dummy(range.top);
        for (items[range.start..range.end]) |message| {
            const line = self.bubbleLine(scratch, message) catch continue;
            _ = widgets.bubble(line, message.is_outgoing);
            drawDownload(session, message);
        }
        if (range.bottom > 0) gfx.dummy(range.bottom);
    }

    /// Measures every bubble of the open chat. The cache survives until the
    /// chat, the history, or the pane width changes.
    fn measureHeights(
        self: *ChatList,
        session: *Session,
        scratch: std.mem.Allocator,
        items: []const MessageEntry,
    ) !void {
        const width = gfx.availWidth();
        const chat_id = session.state.selectedChatId() orelse 0;
        const last_id = if (items.len > 0) items[items.len - 1].message_id else 0;
        if (chat_id != self.cached_chat_id) self.jump_to_bottom = true;
        if (chat_id == self.cached_chat_id and
            items.len == self.cached_count and
            last_id == self.cached_last_id and
            width == self.cached_width) return;

        self.heights.clearRetainingCapacity();
        try self.heights.ensureTotalCapacity(scratch, items.len);
        const tokens = theme.current();
        for (items) |message| {
            const line = try self.bubbleLine(scratch, message);
            var height = widgets.bubbleHeight(line);
            // The progress row of a photo is part of the line while the
            // photo itself is not rendered yet.
            if (message.photo_file_id != null) height += gfx.frameHeight() + tokens.spacing.y;
            self.heights.appendAssumeCapacity(height);
        }

        self.cached_chat_id = chat_id;
        self.cached_count = items.len;
        self.cached_last_id = last_id;
        self.cached_width = width;
    }

    /// The text a bubble shows: the sender marker in front of the message.
    fn bubbleLine(
        self: *ChatList,
        scratch: std.mem.Allocator,
        message: MessageEntry,
    ) ![]const u8 {
        _ = self;
        const prefix = if (message.is_outgoing) "you: " else "";
        return scratch.printSentinel("{s}{s}", .{ prefix, message.text }, 0);
    }

    /// Asks for the history above the loaded one; TDLib answers only when
    /// no older page is already in flight.
    fn loadOlder(self: *ChatList, session: *Session, chat_id: i64) void {
        _ = self;
        if (session.state.isHistoryExhausted(chat_id)) return;
        session.loadOlderHistory(chat_id) catch |err| {
            session.reportError("loading older messages", err);
        };
    }

    /// The progress row below an attached photo; drawn while the photo
    /// itself is not rendered yet, so the line height stays stable.
    fn drawDownload(session: *Session, message: MessageEntry) void {
        const file_id = message.photo_file_id orelse return;
        const fraction = if (session.state.fileProgress(file_id)) |progress|
            progress.fraction()
        else
            0;
        widgets.progress(fraction);
    }

    fn send(self: *ChatList, session: *Session) !void {
        const chat_id = session.state.selectedChatId() orelse return;
        const text = std.mem.sliceTo(&self.input, 0);
        if (text.len == 0) return;

        try session.sendMessage(chat_id, text);
        self.input[0] = 0;
    }
};
