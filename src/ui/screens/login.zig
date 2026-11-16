//! The login screen: phone number, code, password and QR code.

const std = @import("std");

const zigram_app = @import("zigram_app");

const gfx = @import("../gfx.zig");
const widgets = @import("../widgets.zig");

const Session = zigram_app.session.Session;

/// What the screen asks the frame loop to do.
pub const Outcome = enum { keep_running, quit };

/// The login flow: phone number, code, 2FA password and QR code.
pub const Login = struct {
    /// Bounded text buffers; ImGui requires a zero-terminated buffer.
    phone: [32]u8 = @splat(0),
    code: [16]u8 = @splat(0),
    password: [64]u8 = @splat(0),

    /// Draws the screen of the current authorization state.
    pub fn draw(self: *Login, session: *Session) Outcome {
        switch (session.currentScreen()) {
            .authorizing => self.drawAuthorizing(session),
            .phone => self.drawPhone(session),
            .code => self.drawCode(session),
            .password => self.drawPassword(session),
            .qr => return self.drawQr(session),
            .fatal => return self.drawFatal(session),
            .ready => {},
        }
        return .keep_running;
    }

    fn drawAuthorizing(self: *Login, session: *Session) void {
        _ = self;
        if (session.isPending()) {
            widgets.text("Authorizing...");
        } else {
            widgets.disabled("waiting for Telegram");
        }
    }

    fn drawPhone(self: *Login, session: *Session) void {
        widgets.text("Enter your phone number:");
        _ = gfx.inputText("Phone", self.phone[0..]);
        if (gfx.button("Sign in") and !session.isPending()) {
            const phone = std.mem.sliceTo(&self.phone, 0);
            if (phone.len > 0) {
                session.sendPhoneNumber(phone) catch |err| {
                    session.reportError("sending the phone number", err);
                };
            }
        }
        if (gfx.button("Sign in by QR code") and !session.isPending()) {
            session.requestQrLogin() catch |err| {
                session.reportError("requesting the QR login", err);
            };
        }
    }

    fn drawCode(self: *Login, session: *Session) void {
        const registered = if (session.update) |update|
            update.state == .wait_code and update.state.wait_code.is_registered
        else
            false;
        widgets.text(if (registered)
            "Enter the login code:"
        else
            "Enter the signup code:");
        _ = gfx.inputText("Code", self.code[0..]);
        if (gfx.button("Continue") and !session.isPending()) {
            const code = std.mem.sliceTo(&self.code, 0);
            if (code.len > 0) {
                session.sendCode(code) catch |err| {
                    session.reportError("sending the code", err);
                };
            }
        }
        if (gfx.button("Resend code") and !session.isPending()) {
            session.resendCode() catch |err| {
                session.reportError("resending the code", err);
            };
        }
        if (gfx.button("Sign in by QR code") and !session.isPending()) {
            session.requestQrLogin() catch |err| {
                session.reportError("requesting the QR login", err);
            };
        }
    }

    fn drawPassword(self: *Login, session: *Session) void {
        widgets.text("Enter your 2FA password:");
        if (session.update) |update| {
            if (update.state == .wait_password) {
                if (update.state.wait_password.password_hint) |hint| {
                    widgets.hint(hint);
                }
            }
        }
        _ = gfx.inputPassword("Password", self.password[0..]);
        if (gfx.button("Continue") and !session.isPending()) {
            const password = std.mem.sliceTo(&self.password, 0);
            if (password.len > 0) {
                session.sendPassword(password) catch |err| {
                    session.reportError("sending the password", err);
                };
            }
        }
    }

    fn drawQr(self: *Login, session: *Session) Outcome {
        _ = self;
        widgets.text("Scan this code in Telegram:");
        widgets.disabled("Settings -> Devices -> Link Desktop Device");
        if (qrLink(session)) |link| {
            widgets.text(link);
        } else {
            widgets.errorText("waiting for the QR link");
        }
        if (gfx.button("Quit")) return .quit;
        return .keep_running;
    }

    fn drawFatal(self: *Login, session: *Session) Outcome {
        _ = self;
        _ = session;
        if (gfx.button("Quit")) return .quit;
        return .keep_running;
    }
};

/// The QR login link of the current authorization state, if any.
fn qrLink(session: *const Session) ?[]const u8 {
    const update = session.update orelse return null;
    if (update.state != .wait_other_device_confirmation) return null;
    return update.state.wait_other_device_confirmation.link;
}
