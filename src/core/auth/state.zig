//! Parsing of `updateAuthorizationState` events into the `State` machine.
//!
//! This file never calls TDLib itself; the caller forwards built request
//! JSON through `td.Client.send`. String payloads are owned copies; free
//! everything with `Update.deinit`.

const std = @import("std");

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
