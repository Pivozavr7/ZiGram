//! The authorization side of the session: applying authorization updates
//! and sending the login data to TDLib.

const std = @import("std");

const zigram = @import("zigram");

const auth = zigram.auth;
const config = @import("config.zig");
const parameters = @import("parameters.zig");
const session = @import("session.zig");

const Session = session.Session;

/// Applies an authorization update to the session; the update is consumed
/// for states that carry payload data and dropped for the rest.
pub fn applyAuthorization(self: *Session, update: *auth.Update) !void {
    const new_state = update.state;
    switch (new_state) {
        // These states carry no screen of their own: keep the current one.
        .other, .logging_out, .closing => {
            update.deinit();
            return;
        },
        else => {},
    }

    if (self.update) |*old| old.deinit();
    self.update = update.*;
    update.* = undefined; // the session owns the update now
    applyAuthorizationState(self, new_state);
}

/// Asks TDLib for the next step of the login flow.
fn applyAuthorizationState(self: *Session, auth_state: auth.State) void {
    const cmd = self.commandSender() catch return;
    switch (auth_state) {
        .wait_tdlib_parameters => {
            if (!cmd.isPending()) {
                sendTdlibParameters(self) catch |err| {
                    self.setStatus(config.describeError(self.allocator, err) catch null);
                };
            }
        },
        .wait_phone_number, .wait_code, .wait_password, .wait_other_device_confirmation => {
            cmd.clearPending();
            self.clearStatus();
        },
        .ready => {
            cmd.clearPending();
            self.clearStatus();
            cmd.loadChats() catch |err| {
                self.setStatus(std.fmt.allocPrint(
                    self.allocator,
                    "loadChats failed: {s}",
                    .{@errorName(err)},
                ) catch null);
            };
        },
        .wait_registration => {
            self.setStatus("Registration of new accounts is not supported yet.");
        },
        .closed => {
            self.setStatus("TDLib closed the session.");
        },
        .other, .logging_out, .closing => {},
    }
}

/// Sends the credentials and the data directories to TDLib.
fn sendTdlibParameters(self: *Session) !void {
    const loaded = self.config orelse return error.ConfigMissing;
    const cmd = try self.commandSender();

    var paths = try parameters.Paths.init(self.allocator, self.home_dir);
    defer paths.deinit();
    try paths.create(self.io);

    try cmd.sendTdlibParameters(.{
        .api_id = @intCast(loaded.api_id),
        .api_hash = loaded.api_hash,
        .database_directory = paths.data_dir,
        .files_directory = paths.files_dir,
    });
}
