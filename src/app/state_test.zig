//! Tests of the application state.

const std = @import("std");

const state = @import("state.zig");
const FileProgress = state.FileProgress;
const State = state.State;

test "chats are inserted and updated" {
    var app_state = State.init(std.testing.allocator);
    defer app_state.deinit();

    try app_state.upsertChat(1, "Alice", 0, 0);
    try app_state.upsertChat(2, "Bob", 0, 0);
    try app_state.upsertChat(1, "Alice Updated", 0, 0);

    try std.testing.expectEqual(@as(usize, 2), app_state.chats.items.len);
    try std.testing.expectEqualStrings("Alice Updated", app_state.chats.items[0].title);
}

test "chats are sorted by the main list order, newest first" {
    var app_state = State.init(std.testing.allocator);
    defer app_state.deinit();

    try app_state.upsertChat(1, "Old", 0, 100);
    try app_state.upsertChat(2, "New", 0, 300);
    try app_state.upsertChat(3, "Middle", 0, 200);

    try std.testing.expectEqual(@as(i64, 2), app_state.chats.items[0].chat_id);
    try std.testing.expectEqual(@as(i64, 3), app_state.chats.items[1].chat_id);
    try std.testing.expectEqual(@as(i64, 1), app_state.chats.items[2].chat_id);

    app_state.setOrder(1, 400);
    try std.testing.expectEqual(@as(i64, 1), app_state.chats.items[0].chat_id);
}

test "unread count is stored and updated" {
    var app_state = State.init(std.testing.allocator);
    defer app_state.deinit();

    try app_state.upsertChat(1, "Alice", 3, 0);
    try std.testing.expectEqual(@as(u32, 3), app_state.chats.items[0].unread_count);

    app_state.setUnread(1, 0);
    try std.testing.expectEqual(@as(u32, 0), app_state.chats.items[0].unread_count);

    app_state.setUnread(42, 5);
    try std.testing.expectEqual(@as(usize, 1), app_state.chats.items.len);
}

test "preview and messages are stored per chat" {
    var app_state = State.init(std.testing.allocator);
    defer app_state.deinit();

    try app_state.upsertChat(1, "Alice", 0, 0);
    try app_state.setPreview(1, "hi there");
    try app_state.appendMessage(10, 1, false, "hi there", 1700000000, null);
    try app_state.appendMessage(11, 2, true, "ignored", 1700000001, null);

    try std.testing.expectEqualStrings("hi there", app_state.chats.items[0].preview);
    try std.testing.expectEqual(@as(usize, 1), app_state.messagesFor(1).len);
    try std.testing.expectEqualStrings("hi there", app_state.messagesFor(1)[0].text);
    try std.testing.expectEqual(@as(usize, 1), app_state.messagesFor(2).len);
}

test "selection reports changes" {
    var app_state = State.init(std.testing.allocator);
    defer app_state.deinit();

    try std.testing.expect(app_state.selectChat(5));
    try std.testing.expect(!app_state.selectChat(5));
    try std.testing.expectEqual(@as(?i64, 5), app_state.selectedChatId());
}

test "file download progress is stored per file" {
    var app_state = State.init(std.testing.allocator);
    defer app_state.deinit();

    try std.testing.expectEqual(@as(?FileProgress, null), app_state.fileProgress(901));

    try app_state.setFileProgress(.{ .file_id = 901, .downloaded = 100, .size = 400 });
    const progress = app_state.fileProgress(901).?;
    try std.testing.expectEqual(@as(f32, 0.25), progress.fraction());
    try std.testing.expect(!progress.is_completed);

    try app_state.setFileProgress(.{ .file_id = 901, .downloaded = 400, .size = 400, .is_completed = true });
    try std.testing.expect(app_state.fileProgress(901).?.is_completed);
    try std.testing.expectEqual(@as(f32, 1), app_state.fileProgress(901).?.fraction());
}

test "messages stay ordered by id and duplicates are ignored" {
    var app_state = State.init(std.testing.allocator);
    defer app_state.deinit();

    // A loaded history first, then older pages prepended by id.
    try app_state.appendMessage(10, 1, false, "third", 1700000002, null);
    try app_state.appendMessage(30, 1, true, "fifth", 1700000004, null);
    try app_state.appendMessage(20, 1, false, "fourth", 1700000003, null);
    try app_state.appendMessage(10, 1, false, "third again", 1700000002, null);
    // The first page of the history, older than everything stored.
    try app_state.appendMessage(5, 1, false, "first", 1700000000, null);
    try app_state.appendMessage(1, 2, true, "other chat", 1700000000, null);

    const items = app_state.messagesFor(1);
    try std.testing.expectEqual(@as(usize, 4), items.len);
    try std.testing.expectEqualStrings("first", items[0].text);
    try std.testing.expectEqualStrings("third", items[1].text);
    try std.testing.expectEqualStrings("fifth", items[3].text);
    try std.testing.expectEqual(@as(?i64, 5), app_state.oldestMessageId(1));
    try std.testing.expectEqual(@as(?i64, 1), app_state.oldestMessageId(2));
    try std.testing.expectEqual(@as(?i64, null), app_state.oldestMessageId(404));
}

test "history exhaustion is tracked per chat" {
    var app_state = State.init(std.testing.allocator);
    defer app_state.deinit();

    // An unknown chat counts as exhausted: there is nothing to scroll to.
    try std.testing.expect(app_state.isHistoryExhausted(1));

    try app_state.appendMessage(10, 1, false, "hi", 1700000000, null);
    app_state.setHistoryExhausted(1, false);
    try std.testing.expect(!app_state.isHistoryExhausted(1));

    app_state.setHistoryExhausted(1, true);
    try std.testing.expect(app_state.isHistoryExhausted(1));
}
