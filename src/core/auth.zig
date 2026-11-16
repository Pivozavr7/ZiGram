//! Authorization state machine: parsing of `updateAuthorizationState`
//! events and builders for the requests TDLib expects during login.
//!
//! This file never calls TDLib itself; the caller forwards built request
//! JSON through `td.Client.send`.

const std = @import("std");

const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

/// Parsed `authorizationState*`. String payloads are owned copies; free
/// everything with `Update.deinit`.
pub const State = union(enum) {
    /// Call `setTdlibParametersRequest`.
    wait_tdlib_parameters,
    /// Call `setAuthenticationPhoneNumberRequest`.
    wait_phone_number,
    wait_code: struct { is_registered: bool },
    wait_password: struct { password_hint: ?[]u8 },
    /// Scan the QR link in an already authorized Telegram app.
    wait_other_device_confirmation: struct { link: []u8 },
    wait_registration,
    ready,
    logging_out,
    closing,
    closed,
    /// Unknown `authorizationState*` type; the name is an owned copy so a
    /// caller can log or ignore it.
    other: []u8,
};

pub const ParseError = std.json.ParseError(std.json.Scanner) || Allocator.Error;

pub const RequestError = Allocator.Error || error{WriteFailed};

/// An owned authorization-state update.
pub const Update = struct {
    allocator: Allocator,
    state: State,

    pub fn deinit(self: *Update) void {
        switch (self.state) {
            .wait_password => |payload| {
                if (payload.password_hint) |hint| self.allocator.free(hint);
            },
            .wait_other_device_confirmation => |payload| {
                self.allocator.free(payload.link);
            },
            .other => |name| self.allocator.free(name),
            else => {},
        }
        self.* = undefined;
    }

    /// Returns null when `event_json` is not an authorization-state update.
    /// Unknown fields are ignored on purpose: TDLib adds fields between
    /// versions.
    pub fn parse(
        allocator: Allocator,
        event_json: []const u8,
    ) ParseError!?Update {
        var parsed = try std.json.parseFromSlice(
            ParsedUpdate,
            allocator,
            event_json,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();

        const update = parsed.value;
        if (!std.mem.eql(u8, update.@"@type", "updateAuthorizationState")) {
            return null;
        }

        const authorization = update.authorization_state orelse return null;
        const payload_type = authorization.@"@type";

        var state: State = undefined;
        if (std.mem.eql(u8, payload_type, "authorizationStateWaitTdlibParameters")) {
            state = .wait_tdlib_parameters;
        } else if (std.mem.eql(u8, payload_type, "authorizationStateWaitPhoneNumber")) {
            state = .wait_phone_number;
        } else if (std.mem.eql(u8, payload_type, "authorizationStateWaitCode")) {
            state = .{ .wait_code = .{ .is_registered = authorization.is_registered } };
        } else if (std.mem.eql(u8, payload_type, "authorizationStateWaitPassword")) {
            const hint: ?[]u8 = if (authorization.password_hint) |hint|
                try allocator.dupe(u8, hint)
            else
                null;
            state = .{ .wait_password = .{ .password_hint = hint } };
        } else if (std.mem.eql(u8, payload_type, "authorizationStateWaitOtherDeviceConfirmation")) {
            const link = authorization.link orelse {
                state = .{ .other = try allocator.dupe(u8, payload_type) };
                return .{ .allocator = allocator, .state = state };
            };
            state = .{ .wait_other_device_confirmation = .{
                .link = try allocator.dupe(u8, link),
            } };
        } else if (std.mem.eql(u8, payload_type, "authorizationStateWaitRegistration")) {
            state = .wait_registration;
        } else if (std.mem.eql(u8, payload_type, "authorizationStateReady")) {
            state = .ready;
        } else if (std.mem.eql(u8, payload_type, "authorizationStateLoggingOut")) {
            state = .logging_out;
        } else if (std.mem.eql(u8, payload_type, "authorizationStateClosing")) {
            state = .closing;
        } else if (std.mem.eql(u8, payload_type, "authorizationStateClosed")) {
            state = .closed;
        } else {
            state = .{ .other = try allocator.dupe(u8, payload_type) };
        }

        return .{ .allocator = allocator, .state = state };
    }
};

const AuthStatePayload = struct {
    @"@type": []const u8,
    is_registered: bool = false,
    password_hint: ?[]const u8 = null,
    /// Login link for `authorizationStateWaitOtherDeviceConfirmation`.
    link: ?[]const u8 = null,
};

const ParsedUpdate = struct {
    @"@type": []const u8,
    authorization_state: ?AuthStatePayload = null,
};

/// Application credentials and paths for `setTdlibParameters`.
pub const Parameters = struct {
    /// Obtained at https://my.telegram.org; the caller owns keeping this
    /// out of logs and the repository.
    api_id: i32,
    api_hash: []const u8,
    database_directory: []const u8,
    files_directory: []const u8,
    system_language_code: []const u8 = "en",
    device_model: []const u8 = "ZiGram",
    application_version: []const u8 = "0.0.0",
    use_message_database: bool = true,
    use_secret_chats: bool = false,
};

const FieldValue = union(enum) {
    string: []const u8,
    int: i64,
    boolean: bool,
};

const Field = struct {
    name: []const u8,
    value: FieldValue,
};

/// Builds `{"@type":<type_name>,<field>,...}` with proper string escaping.
/// Zig field names cannot contain `@`, so requests are assembled here
/// instead of through `std.json.Stringify.valueAlloc`.
fn buildRequest(
    allocator: Allocator,
    type_name: []const u8,
    fields: []const Field,
) RequestError![]u8 {
    var aw: std.Io.Writer.Allocating = try .initCapacity(allocator, 128);
    errdefer aw.deinit();
    const writer = &aw.writer;

    try writer.writeAll("{\"@type\":");
    try std.json.Stringify.encodeJsonString(type_name, .{}, writer);
    for (fields) |field| {
        try writer.writeAll(",");
        try std.json.Stringify.encodeJsonString(field.name, .{}, writer);
        try writer.writeAll(":");
        switch (field.value) {
            .string => |string| try std.json.Stringify.encodeJsonString(string, .{}, writer),
            .int => |int| try writer.print("{d}", .{int}),
            .boolean => |boolean| try writer.writeAll(if (boolean) "true" else "false"),
        }
    }
    try writer.writeAll("}");
    return aw.toOwnedSlice();
}

/// Builds `setTdlibParameters` JSON. The caller owns the result.
pub fn setTdlibParametersRequest(
    allocator: Allocator,
    parameters: Parameters,
) RequestError![]u8 {
    assert(parameters.api_id != 0);
    assert(parameters.api_hash.len > 0);

    return buildRequest(allocator, "setTdlibParameters", &.{
        .{ .name = "database_directory", .value = .{ .string = parameters.database_directory } },
        .{ .name = "files_directory", .value = .{ .string = parameters.files_directory } },
        .{ .name = "system_language_code", .value = .{ .string = parameters.system_language_code } },
        .{ .name = "device_model", .value = .{ .string = parameters.device_model } },
        .{ .name = "application_version", .value = .{ .string = parameters.application_version } },
        .{ .name = "api_id", .value = .{ .int = parameters.api_id } },
        .{ .name = "api_hash", .value = .{ .string = parameters.api_hash } },
        .{ .name = "use_message_database", .value = .{ .boolean = parameters.use_message_database } },
        .{ .name = "use_secret_chats", .value = .{ .boolean = parameters.use_secret_chats } },
    });
}

/// Builds `setAuthenticationPhoneNumber` JSON. The caller owns the result.
pub fn setAuthenticationPhoneNumberRequest(
    allocator: Allocator,
    phone_number: []const u8,
) RequestError![]u8 {
    assert(phone_number.len > 0);

    return buildRequest(allocator, "setAuthenticationPhoneNumber", &.{
        .{ .name = "phone_number", .value = .{ .string = phone_number } },
    });
}

/// Builds `checkAuthenticationCode` JSON. The caller owns the result.
pub fn checkAuthenticationCodeRequest(
    allocator: Allocator,
    code: []const u8,
) RequestError![]u8 {
    assert(code.len > 0);

    return buildRequest(allocator, "checkAuthenticationCode", &.{
        .{ .name = "code", .value = .{ .string = code } },
    });
}

/// Builds `checkAuthenticationPassword` JSON. The caller owns the result.
pub fn checkAuthenticationPasswordRequest(
    allocator: Allocator,
    password: []const u8,
) RequestError![]u8 {
    assert(password.len > 0);

    return buildRequest(allocator, "checkAuthenticationPassword", &.{
        .{ .name = "password", .value = .{ .string = password } },
    });
}

/// Builds `resendAuthenticationCode` JSON: asks TDLib to send the login code
/// again, for example when it never reached the user's Telegram app.
pub fn resendAuthenticationCodeRequest(allocator: Allocator) RequestError![]u8 {
    return buildRequest(allocator, "resendAuthenticationCode", &.{});
}

/// Builds `requestQrCodeAuthentication` JSON: TDLib answers with a login link
/// that the user scans in an already authorized Telegram app.
pub fn requestQrCodeAuthenticationRequest(allocator: Allocator) RequestError![]u8 {
    return buildRequest(allocator, "requestQrCodeAuthentication", &.{});
}

test "parse recognizes wait tdlib parameters" {
    var update = (try Update.parse(
        std.testing.allocator,
        "{\"@type\":\"updateAuthorizationState\",\"authorization_state\":{\"@type\":\"authorizationStateWaitTdlibParameters\",\"extra\":1}}",
    )) orelse return error.TestUnexpectedResult;
    defer update.deinit();

    try std.testing.expect(update.state == .wait_tdlib_parameters);
}

test "parse recognizes wait code" {
    var update = (try Update.parse(
        std.testing.allocator,
        "{\"@type\":\"updateAuthorizationState\",\"authorization_state\":{\"@type\":\"authorizationStateWaitCode\",\"is_registered\":true}}",
    )) orelse return error.TestUnexpectedResult;
    defer update.deinit();

    try std.testing.expect(update.state == .wait_code);
    try std.testing.expect(update.state.wait_code.is_registered);
}

test "parse copies the password hint" {
    var update = (try Update.parse(
        std.testing.allocator,
        "{\"@type\":\"updateAuthorizationState\",\"authorization_state\":{\"@type\":\"authorizationStateWaitPassword\",\"password_hint\":\"hint text\"}}",
    )) orelse return error.TestUnexpectedResult;
    defer update.deinit();

    try std.testing.expect(update.state == .wait_password);
    try std.testing.expectEqualStrings(
        "hint text",
        update.state.wait_password.password_hint.?,
    );
}

test "parse returns null for other updates" {
    const maybe = try Update.parse(
        std.testing.allocator,
        "{\"@type\":\"updateNewMessage\",\"message\":{}}",
    );

    try std.testing.expectEqual(@as(?Update, null), maybe);
}

test "parse keeps unknown state types" {
    var update = (try Update.parse(
        std.testing.allocator,
        "{\"@type\":\"updateAuthorizationState\",\"authorization_state\":{\"@type\":\"authorizationStateWaitSomethingNew\"}}",
    )) orelse return error.TestUnexpectedResult;
    defer update.deinit();

    try std.testing.expect(update.state == .other);
    try std.testing.expectEqualStrings(
        "authorizationStateWaitSomethingNew",
        update.state.other,
    );
}

test "tdlib parameters request is encoded" {
    const json = try setTdlibParametersRequest(std.testing.allocator, .{
        .api_id = 123,
        .api_hash = "hash",
        .database_directory = "/data/db",
        .files_directory = "/data/files",
    });
    defer std.testing.allocator.free(json);

    try std.testing.expectEqualStrings(
        "{\"@type\":\"setTdlibParameters\",\"database_directory\":\"/data/db\",\"files_directory\":\"/data/files\",\"system_language_code\":\"en\",\"device_model\":\"ZiGram\",\"application_version\":\"0.0.0\",\"api_id\":123,\"api_hash\":\"hash\",\"use_message_database\":true,\"use_secret_chats\":false}",
        json,
    );
}

test "requests escape string values" {
    const json = try checkAuthenticationCodeRequest(
        std.testing.allocator,
        "1\"2\\",
    );
    defer std.testing.allocator.free(json);

    try std.testing.expectEqualStrings(
        "{\"@type\":\"checkAuthenticationCode\",\"code\":\"1\\\"2\\\\\"}",
        json,
    );
}

test "phone number and password requests are encoded" {
    const phone = try setAuthenticationPhoneNumberRequest(
        std.testing.allocator,
        "+15551234567",
    );
    defer std.testing.allocator.free(phone);
    try std.testing.expectEqualStrings(
        "{\"@type\":\"setAuthenticationPhoneNumber\",\"phone_number\":\"+15551234567\"}",
        phone,
    );

    const password = try checkAuthenticationPasswordRequest(
        std.testing.allocator,
        "secret",
    );
    defer std.testing.allocator.free(password);
    try std.testing.expectEqualStrings(
        "{\"@type\":\"checkAuthenticationPassword\",\"password\":\"secret\"}",
        password,
    );
}

test "resend code request is encoded" {
    const resend = try resendAuthenticationCodeRequest(std.testing.allocator);
    defer std.testing.allocator.free(resend);

    try std.testing.expectEqualStrings(
        "{\"@type\":\"resendAuthenticationCode\"}",
        resend,
    );
}

test "parse copies the QR login link" {
    var update = (try Update.parse(
        std.testing.allocator,
        "{\"@type\":\"updateAuthorizationState\",\"authorization_state\":{\"@type\":\"authorizationStateWaitOtherDeviceConfirmation\",\"link\":\"tg://login?token=abc\"}}",
    )) orelse return error.TestUnexpectedResult;
    defer update.deinit();

    try std.testing.expect(update.state == .wait_other_device_confirmation);
    try std.testing.expectEqualStrings(
        "tg://login?token=abc",
        update.state.wait_other_device_confirmation.link,
    );
}

test "qr request is encoded" {
    const json = try requestQrCodeAuthenticationRequest(std.testing.allocator);
    defer std.testing.allocator.free(json);

    try std.testing.expectEqualStrings(
        "{\"@type\":\"requestQrCodeAuthentication\"}",
        json,
    );
}
