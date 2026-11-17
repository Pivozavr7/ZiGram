//! Builders for the requests TDLib expects during login.
//!
//! This file never calls TDLib itself; the caller forwards built request
//! JSON through `td.Client.send`.

const std = @import("std");

const request = @import("../request.zig");

const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

pub const RequestError = request.Error;

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

/// Builds `{"@type":<type_name>,<field>,...}` with proper string escaping.
/// Zig field names cannot contain `@`, so requests are assembled here
/// instead of through `std.json.Stringify.valueAlloc`.
fn buildRequest(
    allocator: Allocator,
    type_name: []const u8,
    fields: []const request.Field,
) RequestError![]u8 {
    return request.build(allocator, type_name, fields);
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

test "qr request is encoded" {
    const json = try requestQrCodeAuthenticationRequest(std.testing.allocator);
    defer std.testing.allocator.free(json);

    try std.testing.expectEqualStrings(
        "{\"@type\":\"requestQrCodeAuthentication\"}",
        json,
    );
}
