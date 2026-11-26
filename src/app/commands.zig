//! The commands the screens ask for.
//!
//! Every command builds a TDLib request and sends it through the client.
//! The answer is matched by `@extra`, so the sender remembers what every
//! in-flight request was about.

const std = @import("std");

const zigram = @import("zigram");

const auth = zigram.auth;
const chats = zigram.chats;
const td = zigram.td;

const Allocator = std.mem.Allocator;

/// How many messages one history page asks for.
const history_page_size: u32 = 50;

/// Which login request is waiting for an answer.
pub const Pending = enum {
    none,
    tdlib_parameters,
    phone_number,
    code,
    password,
    resend,
    qr_request,
};

/// What a chat request was about; used to route the answer.
pub const Kind = enum {
    load_chats,
    get_chat,
    history,
    send_message,
    view_messages,
    download_file,
};

/// A request sent to TDLib that has not answered yet.
pub const Request = struct {
    extra: u64,
    kind: Kind,
    /// Chat the request belongs to; 0 when it belongs to no chat.
    chat_id: i64 = 0,
    /// Page size of a history request; 0 for the other kinds.
    limit: u32 = 0,
};

/// Sends commands to TDLib and keeps track of the pending requests.
pub const Commands = struct {
    allocator: Allocator,
    client: *td.Client,
    requests: std.ArrayList(Request),
    pending: Pending = .none,
    pending_extra: u64 = 0,

    pub fn init(allocator: Allocator, client: *td.Client) Commands {
        return .{
            .allocator = allocator,
            .client = client,
            .requests = .empty,
        };
    }

    pub fn deinit(self: *Commands) void {
        self.requests.deinit(self.allocator);
        self.* = undefined;
    }

    /// Sends the credentials and the data directories to TDLib.
    pub fn sendTdlibParameters(self: *Commands, params: auth.Parameters) !void {
        const json = try auth.setTdlibParametersRequest(self.allocator, params);
        defer self.allocator.free(json);
        try self.sendLogin(.tdlib_parameters, json);
    }

    /// Sends the phone number of the account.
    pub fn sendPhoneNumber(self: *Commands, phone: []const u8) !void {
        const json = try auth.setAuthenticationPhoneNumberRequest(self.allocator, phone);
        defer self.allocator.free(json);
        try self.sendLogin(.phone_number, json);
    }

    /// Sends the login code.
    pub fn sendCode(self: *Commands, code: []const u8) !void {
        const json = try auth.checkAuthenticationCodeRequest(self.allocator, code);
        defer self.allocator.free(json);
        try self.sendLogin(.code, json);
    }

    /// Sends the 2FA password.
    pub fn sendPassword(self: *Commands, password: []const u8) !void {
        const json = try auth.checkAuthenticationPasswordRequest(self.allocator, password);
        defer self.allocator.free(json);
        try self.sendLogin(.password, json);
    }

    /// Asks TDLib to send the login code again.
    pub fn resendCode(self: *Commands) !void {
        const json = try auth.resendAuthenticationCodeRequest(self.allocator);
        defer self.allocator.free(json);
        try self.sendLogin(.resend, json);
    }

    /// Asks TDLib for a QR login link.
    pub fn requestQrLogin(self: *Commands) !void {
        const json = try auth.requestQrCodeAuthenticationRequest(self.allocator);
        defer self.allocator.free(json);
        try self.sendLogin(.qr_request, json);
    }

    /// Asks TDLib for the main chat list.
    pub fn loadChats(self: *Commands) !void {
        const json = try chats.loadChatsRequest(self.allocator, 50);
        defer self.allocator.free(json);
        try self.sendChat(.load_chats, json, 0);
    }

    /// Asks TDLib for the metadata of one chat.
    pub fn loadChat(self: *Commands, chat_id: i64) !void {
        const json = try chats.getChatRequest(self.allocator, chat_id);
        defer self.allocator.free(json);
        try self.sendChat(.get_chat, json, chat_id);
    }

    /// Asks TDLib for the newest messages of a chat.
    pub fn loadHistory(self: *Commands, chat_id: i64) !void {
        try self.sendHistory(chat_id, 0);
    }

    /// Asks TDLib for the messages older than `from_message_id`.
    pub fn loadOlderHistory(self: *Commands, chat_id: i64, from_message_id: i64) !void {
        try self.sendHistory(chat_id, from_message_id);
    }

    /// Sends a text message to a chat.
    pub fn sendMessage(self: *Commands, chat_id: i64, text: []const u8) !void {
        const json = try chats.sendMessageRequest(self.allocator, chat_id, text);
        defer self.allocator.free(json);
        try self.sendChat(.send_message, json, chat_id);
    }

    /// Tells TDLib that the messages are shown, so they are marked as read.
    pub fn markRead(self: *Commands, chat_id: i64, message_ids: []const i64) !void {
        if (message_ids.len == 0) return;
        const json = try chats.viewMessagesRequest(self.allocator, chat_id, message_ids);
        defer self.allocator.free(json);
        try self.sendChat(.view_messages, json, chat_id);
    }

    /// Asks TDLib to download a file; the progress arrives as `updateFile`.
    pub fn downloadFile(self: *Commands, file_id: i32) !void {
        const json = try zigram.files.downloadFileRequest(self.allocator, file_id);
        defer self.allocator.free(json);
        try self.sendChat(.download_file, json, 0);
    }

    /// True while a history page of the chat still waits for an answer.
    pub fn isLoadingHistory(self: *const Commands, chat_id: i64) bool {
        for (self.requests.items) |request| {
            if (request.kind == .history and request.chat_id == chat_id) return true;
        }
        return false;
    }

    /// Removes and returns the request with the given `@extra`.
    pub fn take(self: *Commands, extra: u64) ?Request {
        for (self.requests.items, 0..) |*request, index| {
            if (request.extra != extra) continue;
            return self.requests.swapRemove(index);
        }
        return null;
    }

    /// Marks the pending login request as answered.
    pub fn clearPending(self: *Commands) void {
        self.pending = .none;
        self.pending_extra = 0;
    }

    /// True while a login request waits for its answer.
    pub fn isPending(self: *const Commands) bool {
        return self.pending != .none;
    }

    fn sendLogin(self: *Commands, pending: Pending, json: []const u8) !void {
        self.pending = pending;
        self.pending_extra = self.client.send(json) catch |err| {
            self.clearPending();
            return err;
        };
    }

    fn sendChat(self: *Commands, kind: Kind, json: []const u8, chat_id: i64) !void {
        const extra = try self.client.send(json);
        try self.requests.append(self.allocator, .{
            .extra = extra,
            .kind = kind,
            .chat_id = chat_id,
        });
    }

    /// One page of a chat history; the page size is remembered on the
    /// request so the answer can tell a full page from the end of history.
    fn sendHistory(self: *Commands, chat_id: i64, from_message_id: i64) !void {
        const json = try chats.getChatHistoryRequest(
            self.allocator,
            chat_id,
            from_message_id,
            @intCast(history_page_size),
        );
        defer self.allocator.free(json);
        const extra = try self.client.send(json);
        try self.requests.append(self.allocator, .{
            .extra = extra,
            .kind = .history,
            .chat_id = chat_id,
            .limit = history_page_size,
        });
    }
};

/// Extracts `message` from a TDLib error response, or null for successes.
pub fn errorText(allocator: Allocator, response_json: []const u8) !?[]const u8 {
    const Response = struct {
        @"@type": []const u8,
        message: ?[]const u8 = null,
    };
    var parsed = try std.json.parseFromSlice(
        Response,
        allocator,
        response_json,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    if (std.mem.eql(u8, parsed.value.@"@type", "error")) {
        return try allocator.dupe(u8, parsed.value.message orelse "unknown error");
    }
    return null;
}

test "an error response carries a message" {
    const text = (try errorText(
        std.testing.allocator,
        "{\"@type\":\"error\",\"code\":400,\"message\":\"CHAT_NOT_FOUND\"}",
    )).?;
    defer std.testing.allocator.free(text);

    try std.testing.expectEqualStrings("CHAT_NOT_FOUND", text);
}

test "a successful response has no message" {
    const text = try errorText(std.testing.allocator, "{\"@type\":\"ok\"}");
    try std.testing.expectEqual(@as(?[]const u8, null), text);
}
