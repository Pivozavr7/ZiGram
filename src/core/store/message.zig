//! The `Message` store model and its TDLib payload.

const std = @import("std");

const common = @import("common.zig");

const Allocator = std.mem.Allocator;

pub const ParseError = common.ParseError;

/// Who sent a message; TDLib `messageSender*`.
pub const Sender = union(enum) {
    user: i64,
    chat: i64,
    /// Unknown `messageSender*` name; owned copy.
    other: []u8,
    /// The sender was missing from the payload.
    unknown,
};

/// What a message contains; ZiGram models previews, media arrives later.
pub const Content = union(enum) {
    /// Owned copy of the plain text of a `messageText`.
    text: []u8,
    /// Any other `message*` content; the owned type name lets the UI show a
    /// placeholder like `[sticker]`.
    other: []u8,
    /// The content was missing from the payload.
    unknown,
};

/// A message from history or an update.
pub const Message = struct {
    id: i64,
    chat_id: i64,
    sender: Sender,
    /// Unix timestamp in seconds; TDLib sends `i32` dates.
    date: i32,
    is_outgoing: bool,
    content: Content,

    allocator: Allocator,

    pub fn deinit(self: *Message) void {
        switch (self.sender) {
            .other => |name| self.allocator.free(name),
            else => {},
        }
        deinitContent(self.allocator, &self.content);
        self.* = undefined;
    }

    /// Parses the JSON of a single `message` object. The caller owns the result.
    pub fn parse(allocator: Allocator, json: []const u8) ParseError!Message {
        var parsed = try std.json.parseFromSlice(
            MessagePayload,
            allocator,
            json,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();
        return messageFromPayload(allocator, parsed.value);
    }
};

pub const MessagePayload = struct {
    id: i64 = 0,
    chat_id: i64 = 0,
    sender_id: ?SenderPayload = null,
    date: i32 = 0,
    is_outgoing: bool = false,
    content: ?ContentPayload = null,
};

/// Builds a `Message` from an already-parsed payload. The caller owns the
/// result; used by `Message.parse` and by `updates.zig`.
pub fn messageFromPayload(allocator: Allocator, payload: MessagePayload) Allocator.Error!Message {
    var message: Message = .{
        .allocator = allocator,
        .id = payload.id,
        .chat_id = payload.chat_id,
        .sender = .unknown,
        .date = payload.date,
        .is_outgoing = payload.is_outgoing,
        .content = .unknown,
    };
    errdefer message.deinit();

    if (payload.sender_id) |sender| {
        message.sender = try parseSender(allocator, sender);
    }
    if (payload.content) |content| {
        message.content = try contentFromPayload(allocator, content);
    }
    return message;
}

const SenderPayload = struct {
    @"@type": []const u8,
    user_id: i64 = 0,
    chat_id: i64 = 0,
};

const FormattedText = struct {
    text: []const u8 = "",
};

pub const ContentPayload = struct {
    @"@type": []const u8,
    text: ?FormattedText = null,
};

fn parseSender(allocator: Allocator, payload: SenderPayload) Allocator.Error!Sender {
    const type_name = payload.@"@type";
    if (std.mem.eql(u8, type_name, "messageSenderUser")) {
        return .{ .user = payload.user_id };
    } else if (std.mem.eql(u8, type_name, "messageSenderChat")) {
        return .{ .chat = payload.chat_id };
    } else {
        return .{ .other = try allocator.dupe(u8, type_name) };
    }
}

/// Builds a `Content` from an already-parsed payload; the caller owns the
/// result. Used by `messageFromPayload` and update parsing.
pub fn contentFromPayload(allocator: Allocator, payload: ContentPayload) Allocator.Error!Content {
    const type_name = payload.@"@type";
    if (std.mem.eql(u8, type_name, "messageText")) {
        const text = if (payload.text) |formatted| formatted.text else "";
        return .{ .text = try allocator.dupe(u8, text) };
    } else {
        return .{ .other = try allocator.dupe(u8, type_name) };
    }
}

/// Frees the owned strings of a `Content`; the union itself is not heap.
pub fn deinitContent(allocator: Allocator, content: *Content) void {
    switch (content.*) {
        .text => |text| allocator.free(text),
        .other => |name| allocator.free(name),
        .unknown => {},
    }
    content.* = .unknown;
}

test "message parses text from a user" {
    var message = try Message.parse(
        std.testing.allocator,
        "{\"@type\":\"message\",\"id\":10,\"chat_id\":1001,\"sender_id\":{\"@type\":\"messageSenderUser\",\"user_id\":42},\"date\":1700000000,\"is_outgoing\":true,\"content\":{\"@type\":\"messageText\",\"text\":{\"@type\":\"formattedText\",\"text\":\"hello world\"}},\"extra\":\"ignored\"}",
    );
    defer message.deinit();

    try std.testing.expectEqual(@as(i64, 10), message.id);
    try std.testing.expectEqual(@as(i64, 1001), message.chat_id);
    try std.testing.expectEqual(@as(i64, 42), message.sender.user);
    try std.testing.expectEqual(@as(i32, 1700000000), message.date);
    try std.testing.expect(message.is_outgoing);
    try std.testing.expectEqualStrings("hello world", message.content.text);
}

test "message parses channel sender and non-text content" {
    var message = try Message.parse(
        std.testing.allocator,
        "{\"@type\":\"message\",\"id\":11,\"chat_id\":-1002002,\"sender_id\":{\"@type\":\"messageSenderChat\",\"chat_id\":-1002002},\"content\":{\"@type\":\"messageSticker\"}}",
    );
    defer message.deinit();

    try std.testing.expectEqual(@as(i64, -1002002), message.sender.chat);
    try std.testing.expectEqualStrings("messageSticker", message.content.other);
}

test "message without sender or content stores unknown" {
    var message = try Message.parse(
        std.testing.allocator,
        "{\"@type\":\"message\",\"id\":12,\"chat_id\":1}",
    );
    defer message.deinit();

    try std.testing.expect(message.sender == .unknown);
    try std.testing.expect(message.content == .unknown);
}
