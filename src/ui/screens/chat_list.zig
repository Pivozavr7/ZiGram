//! The chat list, the conversation of the selected chat and the composer.

const std = @import("std");

const zigram_app = @import("zigram_app");

const gfx = @import("../gfx.zig");
const theme = @import("../theme/root.zig");
const widgets = @import("../widgets.zig");

const Session = zigram_app.session.Session;

/// What the screen asks the frame loop to do.
pub const Outcome = enum { keep_running, quit };

/// The two-pane client view: chats on the left, conversation on the right.
pub const ChatList = struct {
    /// Buffer of the message composer.
    input: [4096]u8 = @splat(0),

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
        _ = self;
        const chat_id = session.state.selectedChatId() orelse return;
        for (session.state.messagesFor(chat_id)) |message| {
            const prefix = if (message.is_outgoing) "you: " else "";
            const line = scratch.printSentinel(
                "{s}{s}",
                .{ prefix, message.text },
                0,
            ) catch continue;
            widgets.text(line);
        }
    }

    fn send(self: *ChatList, session: *Session) !void {
        const chat_id = session.state.selectedChatId() orelse return;
        const text = std.mem.sliceTo(&self.input, 0);
        if (text.len == 0) return;

        try session.sendMessage(chat_id, text);
        self.input[0] = 0;
    }
};
