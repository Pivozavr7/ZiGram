//! The application session: owns the TDLib client and drains its events.
//!
//! The session is the only owner of the core client. It applies the events
//! TDLib sends to the application state and turns the answers of the
//! commands into state as well.

const std = @import("std");

const zigram = @import("zigram");

const auth = zigram.auth;
const td = zigram.td;
const updates = zigram.updates;

const chat_updates = @import("chat_updates.zig");
const client = @import("client.zig");
const commands = @import("commands.zig");
const config = @import("config.zig");
const login = @import("login.zig");
const log = @import("log.zig");
const parameters = @import("parameters.zig");
const state = @import("state.zig");

const Allocator = std.mem.Allocator;

/// How many events one frame may process.
const event_budget: usize = 32;

/// How long the shutdown waits for TDLib to confirm the closed state.
const close_timeout_ms: u32 = 5_000;

/// The state of the running application.
pub const Session = struct {
    allocator: Allocator,
    io: std.Io,
    /// The TDLib client; null when the startup failed.
    client: ?*td.Client = null,
    /// Commands to the client; null while there is no client.
    commands: ?commands.Commands = null,
    config: ?config.Config = null,
    /// `$HOME`, used for the TDLib data directories.
    home_dir: []const u8 = "",
    /// The newest authorization state, kept for payload data.
    update: ?auth.Update = null,
    /// Chat list, histories and the current selection.
    state: state.State,
    logger: log.Logger,
    /// The last problem the user has to know about.
    status: ?[]u8 = null,

    /// Starts the core; a failed startup leaves the session without a client
    /// and with a status message.
    pub fn init(
        allocator: Allocator,
        io: std.Io,
        logger: log.Logger,
        environ: *const std.process.Environ.Map,
    ) !Session {
        var session = Session{
            .allocator = allocator,
            .io = io,
            .state = state.State.init(allocator),
            .logger = logger,
        };
        errdefer session.deinit();

        const home = environ.get("HOME") orelse {
            session.setStatus(try config.describeError(allocator, error.HomeNotSet));
            return session;
        };
        session.home_dir = home;

        const loaded = config.load(allocator, io, home) catch |err| {
            session.setStatus(try config.describeError(allocator, err));
            return session;
        };
        session.config = loaded;

        const started = try client.start(session.allocator, session.io, session.logger, loaded);
        session.client = started;
        session.commands = commands.Commands.init(session.allocator, started);
        return session;
    }

    pub fn deinit(self: *Session) void {
        if (self.commands) |*cmd| cmd.deinit();
        if (self.client) |started| {
            // TDLib has to release the client before the process exits,
            // otherwise its background threads outlive the static
            // destructors and abort the process.
            td.closeClient(started, self.allocator, close_timeout_ms) catch {};
            started.deinit();
            self.allocator.destroy(started);
        }
        if (self.config) |*loaded| loaded.deinit(self.allocator);
        if (self.update) |*update| update.deinit();
        if (self.status) |text| self.allocator.free(text);
        self.state.deinit();
        self.* = undefined;
    }

    /// The screen the login flow shows right now.
    pub fn currentScreen(self: *const Session) login.Screen {
        if (self.client == null) return .fatal;
        const update = self.update orelse return .authorizing;
        return login.screenFor(update.state);
    }

    /// True while a login request waits for its answer.
    pub fn isPending(self: *const Session) bool {
        const cmd = self.commands orelse return false;
        return cmd.isPending();
    }

    /// Drains the events of the core; called once per frame.
    pub fn drain(self: *Session) !void {
        const core_client = self.client orelse return;

        var remaining: usize = event_budget;
        while (remaining > 0) : (remaining -= 1) {
            const response = (try core_client.poll(0)) orelse break;
            defer core_client.allocator.free(response.json);
            self.logger.event(response.json);

            var maybe_update = try chat_updates.parseTolerantly(
                auth.Update,
                self.allocator,
                self.logger,
                response.json,
            );
            if (maybe_update) |*update| {
                try self.applyAuthorization(update);
                continue;
            }

            var maybe_event = try chat_updates.parseTolerantly(
                updates.Update,
                self.allocator,
                self.logger,
                response.json,
            );
            if (maybe_event) |*event| {
                defer event.deinit();
                try chat_updates.applyUpdate(&self.state, event.event);
                continue;
            }

            try self.applyResponse(response);
        }
    }

    /// Replaces the status message; the caller keeps the ownership.
    pub fn setStatus(self: *Session, text: ?[]const u8) void {
        if (self.status) |old| self.allocator.free(old);
        self.status = if (text) |value| self.allocator.dupe(u8, value) catch null else null;
    }

    /// Forgets the status message.
    pub fn clearStatus(self: *Session) void {
        self.setStatus(null);
    }

    pub fn sendPhoneNumber(self: *Session, phone: []const u8) !void {
        try (try self.commandSender()).sendPhoneNumber(phone);
    }

    pub fn sendCode(self: *Session, code: []const u8) !void {
        try (try self.commandSender()).sendCode(code);
    }

    pub fn sendPassword(self: *Session, password: []const u8) !void {
        try (try self.commandSender()).sendPassword(password);
    }

    pub fn resendCode(self: *Session) !void {
        try (try self.commandSender()).resendCode();
    }

    pub fn requestQrLogin(self: *Session) !void {
        try (try self.commandSender()).requestQrLogin();
    }

    pub fn loadHistory(self: *Session, chat_id: i64) !void {
        try (try self.commandSender()).loadHistory(chat_id);
    }

    pub fn sendMessage(self: *Session, chat_id: i64, text: []const u8) !void {
        try (try self.commandSender()).sendMessage(chat_id, text);
    }

    pub fn sendMessageReply(
        self: *Session,
        chat_id: i64,
        reply_to_message_id: i64,
        text: []const u8,
    ) !void {
        try (try self.commandSender()).sendMessageReply(chat_id, reply_to_message_id, text);
    }

    pub fn editMessage(self: *Session, chat_id: i64, message_id: i64, text: []const u8) !void {
        try (try self.commandSender()).editMessage(chat_id, message_id, text);
    }

    /// Reports a failed command to the user.
    pub fn reportError(self: *Session, context: []const u8, err: anyerror) void {
        self.setStatus(std.fmt.allocPrint(
            self.allocator,
            "{s} failed: {s}",
            .{ context, @errorName(err) },
        ) catch null);
    }

    fn commandSender(self: *Session) error{ClientMissing}!*commands.Commands {
        if (self.commands) |*cmd| return cmd;
        return error.ClientMissing;
    }

    fn applyAuthorization(self: *Session, update: *auth.Update) !void {
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
        self.applyAuthorizationState(new_state);
    }

    fn applyAuthorizationState(self: *Session, auth_state: auth.State) void {
        const cmd = self.commandSender() catch return;
        switch (auth_state) {
            .wait_tdlib_parameters => {
                if (!cmd.isPending()) {
                    self.sendTdlibParameters() catch |err| {
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

    fn applyResponse(self: *Session, response: td.Response) !void {
        const extra = response.extra orelse return;
        const cmd = self.commandSender() catch return;

        if (cmd.take(extra)) |request| {
            try chat_updates.applyResponse(&self.state, cmd, request, response.json);
            return;
        }
        if (extra == cmd.pending_extra and cmd.isPending()) {
            cmd.clearPending();
            self.setStatus(try commands.errorText(self.allocator, response.json));
        }
    }
};

test "a session without a client shows the fatal screen" {
    var session = Session{
        .allocator = std.testing.allocator,
        .io = undefined,
        .state = state.State.init(std.testing.allocator),
        .commands = null,
        .logger = .{},
    };
    defer session.deinit();

    try std.testing.expectEqual(login.Screen.fatal, session.currentScreen());
}
