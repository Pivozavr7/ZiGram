//! The `Chat` store model and its TDLib payload.

const std = @import("std");

const common = @import("common.zig");

const Allocator = std.mem.Allocator;

pub const ParseError = common.ParseError;

/// Which peer a chat points at; TDLib `chatType*`.
pub const ChatType = union(enum) {
    /// One-on-one chat with the user behind `user_id`.
    private: i64,
    basic_group: i64,
    supergroup: struct {
        id: i64,
        is_channel: bool,
    },
    /// `user_id` is the peer of the secret chat.
    secret: i64,
    /// Unknown `chatType*` name; owned copy so a caller can log or ignore it.
    other: []u8,
    /// The chat type was missing from the payload.
    unknown,
};

/// A chat list entry.
pub const Chat = struct {
    id: i64,
    /// Owned copy; an empty title is stored as an empty slice.
    title: []u8,
    type: ChatType,
    is_marked_as_unread: bool,
    /// Unread message count; never negative after parsing.
    unread_count: u32,
    /// Sort order of the main chat list: bigger is newer, 0 when the chat
    /// has no position there.
    order: i64,

    allocator: Allocator,

    pub fn deinit(self: *Chat) void {
        self.allocator.free(self.title);
        switch (self.type) {
            .other => |name| self.allocator.free(name),
            else => {},
        }
        self.* = undefined;
    }

    /// Parses the JSON of a single `chat` object. The caller owns the result.
    pub fn parse(allocator: Allocator, json: []const u8) ParseError!Chat {
        var parsed = try std.json.parseFromSlice(
            ChatPayload,
            allocator,
            json,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();
        return chatFromPayload(allocator, parsed.value);
    }
};

pub const ChatPayload = struct {
    id: i64 = 0,
    title: []const u8 = "",
    type: ?ChatTypePayload = null,
    is_marked_as_unread: bool = false,
    unread_count: i32 = 0,
    positions: []const PositionPayload = &.{},
};

const PositionPayload = struct {
    list: ?ChatListPayload = null,
    order: []const u8 = "",
};

const ChatListPayload = struct {
    @"@type": []const u8 = "",
};

/// Builds a `Chat` from an already-parsed payload. The caller owns the
/// result; used by `Chat.parse` and by `updates.zig`.
pub fn chatFromPayload(allocator: Allocator, payload: ChatPayload) Allocator.Error!Chat {
    var chat: Chat = .{
        .allocator = allocator,
        .id = payload.id,
        .title = try allocator.dupe(u8, payload.title),
        .type = undefined,
        .is_marked_as_unread = payload.is_marked_as_unread,
        .unread_count = if (payload.unread_count > 0)
            @intCast(payload.unread_count)
        else
            0,
        .order = mainOrder(payload.positions),
    };
    errdefer chat.deinit();
    chat.type = try parseChatType(allocator, payload.type);
    return chat;
}

/// The sort order from the main list position; 0 when the chat is only in
/// other lists or the value is not a number.
fn mainOrder(positions: []const PositionPayload) i64 {
    for (positions) |position| {
        const list = position.list orelse continue;
        if (!std.mem.eql(u8, list.@"@type", "chatListMain")) continue;
        return std.fmt.parseInt(i64, position.order, 10) catch 0;
    }
    return 0;
}

const ChatTypePayload = struct {
    @"@type": []const u8,
    user_id: i64 = 0,
    basic_group_id: i64 = 0,
    supergroup_id: i64 = 0,
    is_channel: bool = false,
    secret_chat_id: i64 = 0,
};

fn parseChatType(
    allocator: Allocator,
    maybe_type: ?ChatTypePayload,
) Allocator.Error!ChatType {
    const payload = maybe_type orelse return .unknown;
    const type_name = payload.@"@type";

    if (std.mem.eql(u8, type_name, "chatTypePrivate")) {
        return .{ .private = payload.user_id };
    } else if (std.mem.eql(u8, type_name, "chatTypeBasicGroup")) {
        return .{ .basic_group = payload.basic_group_id };
    } else if (std.mem.eql(u8, type_name, "chatTypeSupergroup")) {
        return .{ .supergroup = .{
            .id = payload.supergroup_id,
            .is_channel = payload.is_channel,
        } };
    } else if (std.mem.eql(u8, type_name, "chatTypeSecret")) {
        return .{ .secret = payload.user_id };
    } else {
        return .{ .other = try allocator.dupe(u8, type_name) };
    }
}

test "chat parses private chat" {
    var chat = try Chat.parse(
        std.testing.allocator,
        "{\"@type\":\"chat\",\"id\":1001,\"title\":\"Alice\",\"type\":{\"@type\":\"chatTypePrivate\",\"user_id\":42}}",
    );
    defer chat.deinit();

    try std.testing.expectEqual(@as(i64, 1001), chat.id);
    try std.testing.expectEqualStrings("Alice", chat.title);
    try std.testing.expectEqual(@as(i64, 42), chat.type.private);
}

test "chat parses supergroup and unread mark" {
    var chat = try Chat.parse(
        std.testing.allocator,
        "{\"@type\":\"chat\",\"id\":-1002002,\"title\":\"News\",\"is_marked_as_unread\":true,\"type\":{\"@type\":\"chatTypeSupergroup\",\"supergroup_id\":2002,\"is_channel\":true}}",
    );
    defer chat.deinit();

    try std.testing.expect(chat.is_marked_as_unread);
    try std.testing.expectEqual(@as(i64, 2002), chat.type.supergroup.id);
    try std.testing.expect(chat.type.supergroup.is_channel);
}

test "chat parses unread count and main list order" {
    var chat = try Chat.parse(
        std.testing.allocator,
        "{\"@type\":\"chat\",\"id\":1001,\"title\":\"Alice\",\"unread_count\":7," ++
            "\"positions\":[{\"@type\":\"chatPosition\",\"list\":{\"@type\":\"chatListArchive\"},\"order\":\"5\"}," ++
            "{\"@type\":\"chatPosition\",\"list\":{\"@type\":\"chatListMain\"},\"order\":\"1234567890123456\"}]}",
    );
    defer chat.deinit();

    try std.testing.expectEqual(@as(u32, 7), chat.unread_count);
    try std.testing.expectEqual(@as(i64, 1234567890123456), chat.order);
}

test "chat without main position and with a negative count" {
    var chat = try Chat.parse(
        std.testing.allocator,
        "{\"@type\":\"chat\",\"id\":1001,\"title\":\"A\",\"unread_count\":-2," ++
            "\"positions\":[{\"@type\":\"chatPosition\",\"list\":{\"@type\":\"chatListArchive\"},\"order\":\"5\"}]}",
    );
    defer chat.deinit();

    try std.testing.expectEqual(@as(u32, 0), chat.unread_count);
    try std.testing.expectEqual(@as(i64, 0), chat.order);
}

test "chat keeps unknown chat types" {
    var chat = try Chat.parse(
        std.testing.allocator,
        "{\"@type\":\"chat\",\"id\":1,\"title\":\"?\",\"type\":{\"@type\":\"chatTypeSomethingNew\"}}",
    );
    defer chat.deinit();

    try std.testing.expectEqualStrings("chatTypeSomethingNew", chat.type.other);
}

test "chat without type stores unknown" {
    var chat = try Chat.parse(
        std.testing.allocator,
        "{\"@type\":\"chat\",\"id\":1,\"title\":\"?\"}",
    );
    defer chat.deinit();

    try std.testing.expect(chat.type == .unknown);
}
