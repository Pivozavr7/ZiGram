//! Parsing of small TDLib responses: option values and event headers.
//!
//! These helpers run before the typed store parsing; they only pull the
//! fields ZiGram needs (`value` of a string option, the `@extra` of an
//! event). Unknown fields are ignored on purpose: TDLib adds fields
//! between versions.

const std = @import("std");

pub const OptionParseError =
    std.json.ParseError(std.json.Scanner) ||
    std.mem.Allocator.Error ||
    error{ UnexpectedResponse, TdLibError };

pub const ExtraParseError = std.json.ParseError(std.json.Scanner);

pub const OptionResponse = struct {
    @"@type": []const u8,
    value: ?[]const u8 = null,
    code: ?i64 = null,
    message: ?[]const u8 = null,
};

/// Extracts `value` from a TDLib `optionValueString` response.
pub fn parseOptionString(
    allocator: std.mem.Allocator,
    response_json: []const u8,
) OptionParseError![]u8 {
    var parsed = try std.json.parseFromSlice(
        OptionResponse,
        allocator,
        response_json,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    const response = parsed.value;
    if (std.mem.eql(u8, response.@"@type", "optionValueString")) {
        const value = response.value orelse return error.UnexpectedResponse;
        return allocator.dupe(u8, value);
    }
    if (std.mem.eql(u8, response.@"@type", "error")) {
        return error.TdLibError;
    }
    return error.UnexpectedResponse;
}

const EventHeader = struct {
    @"@type": []const u8,
    @"@extra": ?u64 = null,
};

/// Reads the `@extra` of a raw TDLib event; null for updates.
pub fn parseEventExtra(
    allocator: std.mem.Allocator,
    event_json: []const u8,
) ExtraParseError!?u64 {
    var parsed = try std.json.parseFromSlice(
        EventHeader,
        allocator,
        event_json,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    return parsed.value.@"@extra";
}

const AuthorizationState = struct {
    @"@type": []const u8,
};

const AuthorizationUpdate = struct {
    @"@type": []const u8,
    authorization_state: ?AuthorizationState = null,
};

/// True when the event is the authorization state "closed" update, the
/// answer of TDLib to a `close` request. A malformed event is not closed.
pub fn isAuthorizationClosed(
    allocator: std.mem.Allocator,
    event_json: []const u8,
) bool {
    var parsed = std.json.parseFromSlice(
        AuthorizationUpdate,
        allocator,
        event_json,
        .{ .ignore_unknown_fields = true },
    ) catch return false;
    defer parsed.deinit();

    const state = parsed.value.authorization_state orelse return false;
    return std.mem.eql(u8, state.@"@type", "authorizationStateClosed");
}

test "isAuthorizationClosed recognizes the closed state" {
    try std.testing.expect(isAuthorizationClosed(
        std.testing.allocator,
        "{\"@type\":\"updateAuthorizationState\",\"authorization_state\":{\"@type\":\"authorizationStateClosed\"}}",
    ));
}

test "isAuthorizationClosed ignores other events" {
    try std.testing.expect(!isAuthorizationClosed(
        std.testing.allocator,
        "{\"@type\":\"updateAuthorizationState\",\"authorization_state\":{\"@type\":\"authorizationStateReady\"}}",
    ));
    try std.testing.expect(!isAuthorizationClosed(
        std.testing.allocator,
        "{\"@type\":\"updateNewMessage\",\"message\":{}}",
    ));
}

test "parseOptionString reads a string option" {
    const version = try parseOptionString(
        std.testing.allocator,
        "{\"@type\":\"optionValueString\",\"value\":\"1.8.70\"}",
    );
    defer std.testing.allocator.free(version);

    try std.testing.expectEqualStrings("1.8.70", version);
}

test "parseOptionString ignores unknown response fields" {
    const version = try parseOptionString(
        std.testing.allocator,
        "{\"@type\":\"optionValueString\",\"value\":\"1.8.70\",\"future\":true}",
    );
    defer std.testing.allocator.free(version);

    try std.testing.expectEqualStrings("1.8.70", version);
}

test "parseOptionString reports a TDLib error" {
    try std.testing.expectError(
        error.TdLibError,
        parseOptionString(
            std.testing.allocator,
            "{\"@type\":\"error\",\"code\":404,\"message\":\"Option not found\"}",
        ),
    );
}

test "parseOptionString rejects an unexpected option type" {
    try std.testing.expectError(
        error.UnexpectedResponse,
        parseOptionString(
            std.testing.allocator,
            "{\"@type\":\"optionValueEmpty\"}",
        ),
    );
}

test "parseEventExtra reads the extra id" {
    const extra = try parseEventExtra(
        std.testing.allocator,
        "{\"@type\":\"updateSome\",\"@extra\":42,\"unknown\":{}}",
    );

    try std.testing.expectEqual(@as(?u64, 42), extra);
}

test "parseEventExtra returns null without an extra id" {
    const extra = try parseEventExtra(
        std.testing.allocator,
        "{\"@type\":\"updateNewMessage\",\"message\":{}}",
    );

    try std.testing.expectEqual(@as(?u64, null), extra);
}
