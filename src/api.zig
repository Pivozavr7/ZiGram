//! C ABI for the iced shell: start and stop the core, exchange JSON events.
//!
//! Zig owns every buffer that crosses this boundary: Rust gets copies
//! allocated with `std.heap.c_allocator` and returns them through
//! `zigram_free`. The shell must call `zigram_stop` for a handle only after
//! all other calls on that handle have finished.

const std = @import("std");
const zigram = @import("zigram");
const app = @import("zigram_app");

const td = zigram.td;
const config = app.config;
const log = app.log;

const Allocator = std.mem.Allocator;

/// Version of this C ABI, returned by `zigram_version`.
const api_version = "0.2.0";

/// How long `zigram_stop` waits for TDLib to confirm the shutdown.
const close_timeout_ms: u32 = 5_000;

/// One running core; the opaque handle Rust receives from `zigram_start`.
const State = struct {
    allocator: Allocator,
    threaded: *std.Io.Threaded,
    io: std.Io,
    client: *td.Client,
    config: config.Config,
    /// Owned `$HOME`; TDLib data directories are built from it.
    home: []const u8,
};

/// A TDLib event handed to the caller. `json` is owned by the caller and is
/// released with `zigram_free(json, len)`.
const Event = extern struct {
    json: ?[*]u8,
    len: usize,
    extra: u64,
    has_extra: c_int,
};

/// Non-secret startup options the shell may pass as JSON. Unknown fields are
/// ignored, so a newer shell stays compatible with an older core.
const StartOptions = struct {
    tdlib_path: ?[]const u8 = null,
};

/// The C ABI version string. The memory is static; never free it.
export fn zigram_version() [*:0]const u8 {
    return api_version;
}

/// Starts the core. `config_json` may be an empty string. Returns null on
/// failure and logs the error name to stderr; credentials are read from
/// `config.zon`, never from this JSON.
export fn zigram_start(config_json: [*:0]const u8) ?*anyopaque {
    return start(std.mem.span(config_json)) catch |err| {
        std.log.err("zigram_start failed: {s}", .{@errorName(err)});
        return null;
    };
}

fn start(config_json: []const u8) !*anyopaque {
    const gpa = std.heap.c_allocator;

    const threaded = try gpa.create(std.Io.Threaded);
    errdefer gpa.destroy(threaded);
    threaded.* = std.Io.Threaded.init(gpa, .{});
    errdefer threaded.deinit();

    const home = try loadHome(gpa);
    errdefer gpa.free(home);

    var cfg = try loadConfig(gpa, threaded.io(), home, config_json);
    errdefer cfg.deinit(gpa);

    const client = try app.client.start(gpa, threaded.io(), log.Logger{}, cfg);
    errdefer {
        td.closeClient(client, gpa, close_timeout_ms) catch {};
        client.deinit();
        gpa.destroy(client);
    }

    const state = try gpa.create(State);
    state.* = .{
        .allocator = gpa,
        .threaded = threaded,
        .io = threaded.io(),
        .client = client,
        .config = cfg,
        .home = home,
    };
    return state;
}

/// Reads `$HOME`; without it the data directories end up relative.
fn loadHome(gpa: Allocator) ![]const u8 {
    const value = std.c.getenv("HOME") orelse return try gpa.dupe(u8, "");
    return try gpa.dupe(u8, std.mem.span(value));
}

/// Loads `config.zon` when present and applies the JSON options on top.
fn loadConfig(
    gpa: Allocator,
    io: std.Io,
    home: []const u8,
    config_json: []const u8,
) !config.Config {
    // A missing or broken config is not fatal for the shell: it starts
    // without credentials and fails later, at login. The ImGui client
    // treats the same situation as fatal.
    var cfg = config.load(gpa, io, home) catch |err| switch (err) {
        error.HomeNotSet,
        error.ConfigMissing,
        error.ConfigInvalid,
        error.ConfigIncomplete,
        error.ParseZon,
        => try emptyConfig(gpa),
        else => return err,
    };
    errdefer cfg.deinit(gpa);

    if (config_json.len > 0) try applyOptions(gpa, &cfg, config_json);
    return cfg;
}

/// A config without credentials; login fails until `config.zon` exists.
fn emptyConfig(gpa: Allocator) !config.Config {
    return .{
        .api_id = 0,
        .api_hash = try gpa.dupe(u8, ""),
        .tdlib_path = null,
    };
}

/// Applies the non-secret JSON options on top of the loaded config.
fn applyOptions(gpa: Allocator, cfg: *config.Config, config_json: []const u8) !void {
    var parsed = std.json.parseFromSlice(StartOptions, gpa, config_json, .{
        .ignore_unknown_fields = true,
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.ConfigJsonInvalid,
    };
    defer parsed.deinit();

    const override_path = parsed.value.tdlib_path orelse return;
    if (cfg.tdlib_path) |old| gpa.free(old);
    cfg.tdlib_path = try gpa.dupe(u8, override_path);
}

/// Stops the core and frees the handle. Passing null is a no-op; passing an
/// already stopped handle is undefined.
export fn zigram_stop(handle: ?*anyopaque) void {
    const state: *State = @ptrCast(@alignCast(handle orelse return));
    stopState(state);
}

fn stopState(state: *State) void {
    // TDLib has to confirm the close before its threads outlive the
    // process; the same order the ImGui session uses.
    td.closeClient(state.client, state.allocator, close_timeout_ms) catch {};
    state.client.deinit();
    state.allocator.destroy(state.client);
    state.config.deinit(state.allocator);
    state.allocator.free(state.home);
    state.threaded.deinit();
    state.allocator.destroy(state.threaded);
    state.allocator.destroy(state);
}

/// Sends one request. Returns the `@extra` assigned by the core, or 0 when
/// the request was rejected.
export fn zigram_send(handle: ?*anyopaque, request_json: [*:0]const u8) u64 {
    const state: *State = @ptrCast(@alignCast(handle orelse return 0));
    return state.client.send(std.mem.span(request_json)) catch 0;
}

/// Sends the credentials and data directories from `config.zon` to TDLib,
/// once per start right after `authorizationStateWaitTdlibParameters`.
/// Returns the assigned `@extra`, or 0 when the config has no credentials.
/// Rust never sees the api id or hash.
export fn zigram_send_tdlib_parameters(handle: ?*anyopaque) u64 {
    const state: *State = @ptrCast(@alignCast(handle orelse return 0));
    return sendTdlibParameters(state) catch |err| {
        std.log.err("zigram_send_tdlib_parameters: {s}", .{@errorName(err)});
        return 0;
    };
}

/// Builds `setTdlibParameters` from the loaded config and the data paths.
fn sendTdlibParameters(state: *State) !u64 {
    const cfg = state.config;
    if (cfg.api_id == 0 or cfg.api_hash.len == 0) return error.ConfigIncomplete;

    var paths = try app.parameters.Paths.init(state.allocator, state.home);
    defer paths.deinit();
    try paths.create(state.io);

    const json = try zigram.auth.setTdlibParametersRequest(state.allocator, .{
        .api_id = @intCast(cfg.api_id),
        .api_hash = cfg.api_hash,
        .database_directory = paths.data_dir,
        .files_directory = paths.files_dir,
    });
    defer state.allocator.free(json);
    return state.client.send(json);
}

/// Waits up to `timeout_ms` for one event. Returns 1 when `out` is filled
/// (the caller then owns `out.json`), 0 on timeout, -1 on error.
export fn zigram_poll_event(handle: ?*anyopaque, timeout_ms: u32, out: *Event) c_int {
    const state: *State = @ptrCast(@alignCast(handle orelse return -1));
    const response = state.client.poll(timeout_ms) catch return -1;
    const event = response orelse return 0;
    out.* = .{
        .json = event.json.ptr,
        .len = event.json.len,
        .extra = event.extra orelse 0,
        .has_extra = @intFromBool(event.extra != null),
    };
    return 1;
}

/// Frees a buffer previously handed out by `zigram_poll_event`.
export fn zigram_free(ptr: ?*anyopaque, len: usize) void {
    const raw = ptr orelse return;
    const bytes: [*]u8 = @ptrCast(@alignCast(raw));
    std.heap.c_allocator.free(bytes[0..len]);
}

test "start options ignore unknown fields" {
    var parsed = try std.json.parseFromSlice(
        StartOptions,
        std.testing.allocator,
        "{\"tdlib_path\":\"/tmp/libtdjson.so\",\"future_field\":true}",
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    try std.testing.expectEqualStrings(
        "/tmp/libtdjson.so",
        parsed.value.tdlib_path.?,
    );
}

test "zigram_version is a non-empty string" {
    const version = std.mem.span(zigram_version());
    try std.testing.expect(version.len > 0);
}

test "zigram_free accepts null and real buffers" {
    zigram_free(null, 0);
    const buffer = try std.heap.c_allocator.dupe(u8, "event");
    zigram_free(buffer.ptr, buffer.len);
}

test "sending tdlib parameters without a handle is rejected" {
    try std.testing.expectEqual(@as(u64, 0), zigram_send_tdlib_parameters(null));
}
