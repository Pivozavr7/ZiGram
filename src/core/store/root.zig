//! Store models: `User`, `Chat`, `Message`, `File` parsed from TDLib JSON.
//!
//! Parsed strings are owned copies; every model frees them with `deinit`.
//! Unknown fields are ignored on purpose: TDLib adds fields between versions.
//! Parsing works on fixed JSON samples only; this module never calls TDLib.
//!
//! Every entity lives in its own file next to its payload parser; this
//! module re-exports the public API.

const user = @import("user.zig");
const chat = @import("chat.zig");
const message = @import("message.zig");
const file = @import("file.zig");
const common = @import("common.zig");

pub const ParseError = common.ParseError;

pub const User = user.User;

pub const Chat = chat.Chat;
pub const ChatType = chat.ChatType;
pub const ChatPayload = chat.ChatPayload;
pub const chatFromPayload = chat.chatFromPayload;

pub const Message = message.Message;
pub const Sender = message.Sender;
pub const Content = message.Content;
pub const MessagePayload = message.MessagePayload;
pub const ContentPayload = message.ContentPayload;
pub const messageFromPayload = message.messageFromPayload;
pub const contentFromPayload = message.contentFromPayload;
pub const deinitContent = message.deinitContent;

pub const File = file.File;

test {
    _ = @import("user.zig");
    _ = @import("chat.zig");
    _ = @import("message.zig");
    _ = @import("file.zig");
}
