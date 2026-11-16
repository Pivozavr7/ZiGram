//! The pure mapping from the authorization state to the screen to show.
//!
//! The function is pure so it can be tested without a TDLib connection.

const std = @import("std");

const zigram = @import("zigram");

const auth = zigram.auth;

/// The screen of the login flow.
pub const Screen = enum {
    /// Waiting for TDLib to accept the first parameters.
    authorizing,
    phone,
    code,
    password,
    /// Waiting for the user to scan the QR link in a Telegram app.
    qr,
    ready,
    /// Unrecoverable problem; the message explains what to do.
    fatal,
};

/// Returns the screen that belongs to an authorization state.
pub fn screenFor(state: auth.State) Screen {
    return switch (state) {
        .wait_tdlib_parameters => .authorizing,
        .wait_phone_number => .phone,
        .wait_code => .code,
        .wait_password => .password,
        .wait_other_device_confirmation => .qr,
        .ready, .logging_out => .ready,
        .wait_registration, .closing, .closed => .fatal,
        .other => .authorizing,
    };
}

test "the phone number screen follows the authorization state" {
    try std.testing.expectEqual(Screen.phone, screenFor(.wait_phone_number));
    try std.testing.expectEqual(Screen.code, screenFor(.{ .wait_code = .{ .is_registered = true } }));
    try std.testing.expectEqual(Screen.password, screenFor(.{ .wait_password = .{ .password_hint = null } }));
}

test "the QR screen follows the authorization state" {
    var link: [20]u8 = "tg://login?token=abc".*;
    try std.testing.expectEqual(
        Screen.qr,
        screenFor(.{ .wait_other_device_confirmation = .{ .link = &link } }),
    );
}

test "the ready screen follows the authorization state" {
    try std.testing.expectEqual(Screen.ready, screenFor(.ready));
    try std.testing.expectEqual(Screen.authorizing, screenFor(.wait_tdlib_parameters));
}

test "a closed session is fatal" {
    try std.testing.expectEqual(Screen.fatal, screenFor(.closed));
    try std.testing.expectEqual(Screen.fatal, screenFor(.wait_registration));
}
