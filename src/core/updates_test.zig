//! Tests of the `update*` event parsing.

const std = @import("std");

const store = @import("store/root.zig");
const updates = @import("updates.zig");

const Update = updates.Update;

test "updateNewChat parses into a chat" {
    var update = (try Update.parse(
        std.testing.allocator,
        "{\"@type\":\"updateNewChat\",\"chat\":{\"@type\":\"chat\",\"id\":1001,\"title\":\"Alice\",\"type\":{\"@type\":\"chatTypePrivate\",\"user_id\":42}},\"extra\":1}",
    )) orelse return error.TestUnexpectedResult;
    defer update.deinit();

    try std.testing.expect(update.event == .new_chat);
    try std.testing.expectEqual(@as(i64, 1001), update.event.new_chat.id);
    try std.testing.expectEqualStrings("Alice", update.event.new_chat.title);
}

test "updateChatLastMessage parses the preview message" {
    var update = (try Update.parse(
        std.testing.allocator,
        "{\"@type\":\"updateChatLastMessage\",\"chat_id\":1001,\"last_message\":{\"@type\":\"message\",\"id\":10,\"chat_id\":1001,\"date\":1700000000,\"content\":{\"@type\":\"messageText\",\"text\":{\"@type\":\"formattedText\",\"text\":\"hello\"}}},\"positions\":[]}",
    )) orelse return error.TestUnexpectedResult;
    defer update.deinit();

    try std.testing.expect(update.event == .chat_last_message);
    try std.testing.expectEqual(@as(i64, 1001), update.event.chat_last_message.chat_id);
    try std.testing.expectEqualStrings(
        "hello",
        update.event.chat_last_message.last_message.?.content.text,
    );
}

test "updateChatLastMessage allows a removed last message" {
    var update = (try Update.parse(
        std.testing.allocator,
        "{\"@type\":\"updateChatLastMessage\",\"chat_id\":1001,\"last_message\":null}",
    )) orelse return error.TestUnexpectedResult;
    defer update.deinit();

    try std.testing.expect(update.event == .chat_last_message);
    try std.testing.expectEqual(@as(?store.Message, null), update.event.chat_last_message.last_message);
}

test "updateNewMessage parses into a message" {
    var update = (try Update.parse(
        std.testing.allocator,
        "{\"@type\":\"updateNewMessage\",\"message\":{\"@type\":\"message\",\"id\":11,\"chat_id\":1001,\"sender_id\":{\"@type\":\"messageSenderUser\",\"user_id\":42},\"date\":1700000001,\"is_outgoing\":false,\"content\":{\"@type\":\"messageText\",\"text\":{\"@type\":\"formattedText\",\"text\":\"hi\"}}}}",
    )) orelse return error.TestUnexpectedResult;
    defer update.deinit();

    try std.testing.expect(update.event == .new_message);
    try std.testing.expectEqualStrings("hi", update.event.new_message.content.text);
    try std.testing.expectEqual(@as(i64, 42), update.event.new_message.sender.user);
}

test "updateChatLastMessage carries the main list order" {
    var update = (try Update.parse(
        std.testing.allocator,
        "{\"@type\":\"updateChatLastMessage\",\"chat_id\":1001,\"last_message\":null," ++
            "\"positions\":[{\"@type\":\"chatPosition\",\"list\":{\"@type\":\"chatListMain\"},\"order\":\"987654321\"}]}",
    )) orelse return error.TestUnexpectedResult;
    defer update.deinit();

    try std.testing.expect(update.event == .chat_last_message);
    try std.testing.expectEqual(@as(i64, 987654321), update.event.chat_last_message.order);
}

test "updateChatReadInbox parses the unread count" {
    var update = (try Update.parse(
        std.testing.allocator,
        "{\"@type\":\"updateChatReadInbox\",\"chat_id\":1001,\"unread_count\":5,\"last_read_inbox_message_id\":20}",
    )) orelse return error.TestUnexpectedResult;
    defer update.deinit();

    try std.testing.expect(update.event == .chat_read_inbox);
    try std.testing.expectEqual(@as(i64, 1001), update.event.chat_read_inbox.chat_id);
    try std.testing.expectEqual(@as(u32, 5), update.event.chat_read_inbox.unread_count);
}

test "updateChatReadInbox clamps a negative count to zero" {
    var update = (try Update.parse(
        std.testing.allocator,
        "{\"@type\":\"updateChatReadInbox\",\"chat_id\":1001,\"unread_count\":-1}",
    )) orelse return error.TestUnexpectedResult;
    defer update.deinit();

    try std.testing.expect(update.event == .chat_read_inbox);
    try std.testing.expectEqual(@as(u32, 0), update.event.chat_read_inbox.unread_count);
}

test "parse keeps unknown update types" {
    var update = (try Update.parse(
        std.testing.allocator,
        "{\"@type\":\"updateSomethingBrandNew\",\"field\":1}",
    )) orelse return error.TestUnexpectedResult;
    defer update.deinit();

    try std.testing.expect(update.event == .other);
    try std.testing.expectEqualStrings("updateSomethingBrandNew", update.event.other);
}

test "parse returns null for responses" {
    const maybe = try Update.parse(
        std.testing.allocator,
        "{\"@type\":\"ok\",\"@extra\":1}",
    );

    try std.testing.expectEqual(@as(?Update, null), maybe);
}

test "parse returns null for error responses whose message is a string" {
    const maybe = try Update.parse(
        std.testing.allocator,
        "{\"@type\":\"error\",\"code\":400,\"message\":\"CHAT_NOT_FOUND\"}",
    );

    try std.testing.expectEqual(@as(?Update, null), maybe);
}

test "a known update with an unexpected payload shape degrades to other" {
    var update = (try Update.parse(
        std.testing.allocator,
        "{\"@type\":\"updateNewMessage\",\"message\":\"not an object\"}",
    )) orelse return error.TestUnexpectedResult;
    defer update.deinit();

    try std.testing.expect(update.event == .other);
    try std.testing.expectEqualStrings("updateNewMessage", update.event.other);
}

test "parse returns null for malformed known updates" {
    const maybe = try Update.parse(
        std.testing.allocator,
        "{\"@type\":\"updateNewChat\"}",
    );

    try std.testing.expectEqual(@as(?Update, null), maybe);
}
