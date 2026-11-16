//! The chat list, the conversation of the selected chat and the composer.

const std = @import("std");

const zigram_app = @import("zigram_app");

const gfx = @import("../gfx.zig");
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
        self.drawChats(session, scratch);
        gfx.sameLine();
        self.drawMessages(session, scratch);

        _ = gfx.inputMultiline("Message", self.input[0..]);
        if (gfx.button("Send")) {
            self.send(session) catch |err| {
                session.reportError("sending the message", err);
            };
        }
        gfx.sameLine();
        if (gfx.button("Quit")) return .quit;
        return .keep_running;
    }

    fn drawChats(self: *ChatList, session: *Session, scratch: std.mem.Allocator) void {
        _ = self;
        if (!gfx.beginChild("Chats", 280, 460)) return;

        if (session.state.chats.items.len == 0) {
            widgets.disabled("no chats yet");
        }
        for (session.state.chats.items) |*entry| {
            const label = scratch.printSentinel(
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
        gfx.endChild();
    }

    fn drawMessages(self: *ChatList, session: *Session, scratch: std.mem.Allocator) void {
        _ = self;
        if (!gfx.beginChild("Messages", 0, 460)) return;

        const chat_id = session.state.selectedChatId();
        if (chat_id) |id| {
            for (session.state.messagesFor(id)) |message| {
                const prefix = if (message.is_outgoing) "you: " else "";
                const line = scratch.printSentinel(
                    "{s}{s}",
                    .{ prefix, message.text },
                    0,
                ) catch continue;
                widgets.text(line);
            }
        } else {
            widgets.disabled("select a chat");
        }
        gfx.endChild();
    }

    fn send(self: *ChatList, session: *Session) !void {
        const chat_id = session.state.selectedChatId() orelse return;
        const text = std.mem.sliceTo(&self.input, 0);
        if (text.len == 0) return;

        try session.sendMessage(chat_id, text);
        self.input[0] = 0;
    }
};
