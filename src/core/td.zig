//! Runtime binding to TDLib's JSON interface (`libtdjson.so`).
//!
//! The library is loaded with `std.DynLib`, so ZiGram builds without TDLib
//! present. This file is the only place that touches TDLib's C ABI; callers
//! receive Zig-owned strings and errors.

const std = @import("std");

const td_options = @import("td/options.zig");
const queue = @import("td/queue.zig");
const search = @import("td/search.zig");

const Io = std.Io;

const assert = std.debug.assert;

test {
    // Pull the tests of the split-up modules into the `td` test target.
    _ = search;
    _ = td_options;
    _ = queue;
}

/// TDLib version ZiGram is developed and tested against.
pub const expected_tdlib_version = "1.8.70";

const version_request = "{\"@type\":\"getOption\",\"name\":\"version\"}";

// Re-exports so `zigram.td.*` keeps working while `td.zig` is split up.
pub const Source = search.Source;
pub const Candidate = search.Candidate;
pub const Candidates = search.Candidates;
pub const SearchOptions = search.SearchOptions;
pub const searchCandidatesAlloc = search.searchCandidatesAlloc;
pub const parseOptionString = td_options.parseOptionString;
pub const parseEventExtra = td_options.parseEventExtra;
pub const EventQueue = queue.EventQueue;

/// Function pointers exported by `libtdjson.so`.
pub const Symbols = struct {
    create_client_id: *const fn () callconv(.c) c_int,
    send: *const fn (c_int, [*:0]const u8) callconv(.c) void,
    receive: *const fn (f64) callconv(.c) ?[*:0]const u8,
    execute: *const fn ([*:0]const u8) callconv(.c) ?[*:0]const u8,

    pub fn load(dynlib: *std.DynLib) ?Symbols {
        return .{
            .create_client_id = dynlib.lookup(
                *const fn () callconv(.c) c_int,
                "td_create_client_id",
            ) orelse return null,
            .send = dynlib.lookup(
                *const fn (c_int, [*:0]const u8) callconv(.c) void,
                "td_send",
            ) orelse return null,
            .receive = dynlib.lookup(
                *const fn (f64) callconv(.c) ?[*:0]const u8,
                "td_receive",
            ) orelse return null,
            .execute = dynlib.lookup(
                *const fn ([*:0]const u8) callconv(.c) ?[*:0]const u8,
                "td_execute",
            ) orelse return null,
        };
    }
};

pub const InitError = error{
    LibraryNotFound,
    MissingSymbols,
} || std.mem.Allocator.Error;

pub const ExecuteError = error{NullResponse} || std.mem.Allocator.Error;

pub const VersionError = ExecuteError || td_options.OptionParseError;

/// A loaded TDLib library and its symbol table.
pub const Library = struct {
    allocator: std.mem.Allocator,
    dynlib: std.DynLib,
    symbols: Symbols,
    path: []u8,
    source: Source,

    /// Tries every candidate in order. A candidate that opens but does not
    /// export all required symbols is skipped, so a broken copy early in the
    /// search order does not block a good one later.
    pub fn init(
        allocator: std.mem.Allocator,
        options: SearchOptions,
    ) InitError!Library {
        var candidates = try searchCandidatesAlloc(allocator, options);
        defer candidates.deinit();

        var found_broken_library = false;
        for (candidates.items) |candidate| {
            var dynlib = std.DynLib.open(candidate.path) catch continue;
            const maybe_symbols = Symbols.load(&dynlib);
            if (maybe_symbols == null) {
                found_broken_library = true;
                dynlib.close();
                continue;
            }

            const owned_path = allocator.dupe(u8, candidate.path) catch |err| {
                dynlib.close();
                return err;
            };
            return .{
                .allocator = allocator,
                .dynlib = dynlib,
                .symbols = maybe_symbols.?,
                .path = owned_path,
                .source = candidate.source,
            };
        }

        if (found_broken_library) return error.MissingSymbols;
        return error.LibraryNotFound;
    }

    pub fn deinit(self: *Library) void {
        self.allocator.free(self.path);
        // Intentionally do not call `dlclose`: TDLib may have background
        // threads and static destructors, and unloading it during shutdown
        // has been observed to crash the process. The library stays mapped
        // until process exit.
        self.* = undefined;
    }

    /// Calls `td_execute` and copies the response before the next call can
    /// invalidate it.
    pub fn execute(
        self: *const Library,
        allocator: std.mem.Allocator,
        request_json: []const u8,
    ) ExecuteError![]u8 {
        const request_z = try allocator.dupeSentinel(u8, request_json, 0);
        defer allocator.free(request_z);

        const response = self.symbols.execute(request_z.ptr) orelse
            return error.NullResponse;
        return allocator.dupe(u8, std.mem.span(response));
    }

    /// Reads TDLib's own version string through `getOption`.
    pub fn getVersion(
        self: *const Library,
        allocator: std.mem.Allocator,
    ) VersionError![]u8 {
        const response = try self.execute(allocator, version_request);
        defer allocator.free(response);
        return parseOptionString(allocator, response);
    }

    /// Adjusts TDLib's internal log verbosity via `td_execute`.
    pub fn setLogVerbosity(
        self: *const Library,
        allocator: std.mem.Allocator,
        level: i32,
    ) VersionError!void {
        const request = try std.fmt.allocPrint(
            allocator,
            "{{\"@type\":\"setLogVerbosityLevel\",\"new_verbosity_level\":{d}}}",
            .{level},
        );
        defer allocator.free(request);

        const response = try self.execute(allocator, request);
        defer allocator.free(response);

        var parsed = try std.json.parseFromSlice(
            td_options.OptionResponse,
            allocator,
            response,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();

        if (std.mem.eql(u8, parsed.value.@"@type", "error")) {
            return error.TdLibError;
        }
    }
};

pub const ClientOptions = struct {
    /// Maximum number of events buffered between the receiver thread and the
    /// consumer.
    event_capacity: usize = 256,
    /// How long `td_receive` blocks before re-checking the stop flag.
    receive_timeout_seconds: f64 = 0.05,
};

pub const ClientInitError = error{ThreadSpawnFailed} || std.mem.Allocator.Error;

pub const ClientSendError = error{InvalidRequest} || std.mem.Allocator.Error;

pub const ClientPollError = error{ InvalidEvent, Canceled } || std.mem.Allocator.Error;

/// A single TDLib event handed over from the receiver thread.
pub const Response = struct {
    /// The caller owns this memory.
    json: []u8,
    /// `@extra` present in the event, or null for updates.
    extra: ?u64,
};

const default_log_verbosity_level: i32 = 1;

/// Owns the receiver thread, the event queue and the pending `@extra` map.
///
/// `init` takes ownership of the passed `Library`; after a successful init the
/// caller must not deinit it separately. Use `poll` to drain events.
pub const Client = struct {
    allocator: std.mem.Allocator,
    io: Io,
    library: Library,
    client_id: c_int,
    receive_timeout_seconds: f64,
    events: EventQueue,
    pending: std.AutoHashMapUnmanaged(u64, void) = .empty,
    pending_mutex: Io.Mutex = .init,
    receiver_thread: ?std.Thread = null,
    stopping: std.atomic.Value(bool) = .init(false),
    next_extra: std.atomic.Value(u64) = .init(1),
    tdlib_version: ?[]u8 = null,

    pub fn init(
        self: *Client,
        allocator: std.mem.Allocator,
        io: Io,
        library: Library,
        options: ClientOptions,
    ) ClientInitError!void {
        assert(options.event_capacity > 0);

        self.* = .{
            .allocator = allocator,
            .io = io,
            .library = library,
            .client_id = library.symbols.create_client_id(),
            .receive_timeout_seconds = options.receive_timeout_seconds,
            .events = undefined,
        };
        self.events = try EventQueue.init(allocator, options.event_capacity);
        errdefer {
            if (self.tdlib_version) |version| allocator.free(version);
            self.library.deinit();
            self.events.deinit(io);
        }

        self.library.setLogVerbosity(allocator, default_log_verbosity_level) catch |err| {
            std.log.warn("setLogVerbosityLevel failed: {s}", .{@errorName(err)});
        };

        self.tdlib_version = self.library.getVersion(allocator) catch null;
        if (self.tdlib_version) |version| {
            if (!std.mem.eql(u8, version, expected_tdlib_version)) {
                std.log.warn(
                    "TDLib version mismatch: expected {s}, got {s}",
                    .{ expected_tdlib_version, version },
                );
            }
        }

        // TDLib 1.8.x (ClientManager-based tdjson) starts delivering
        // spontaneous updates only after the first request has been sent
        // through the client; until then `td_receive` returns null forever.
        // The harmless `getOption` also confirms the client is alive.
        _ = self.send("{\"@type\":\"getOption\",\"name\":\"version\"}") catch |err| {
            std.log.warn("client kickstart send failed: {s}", .{@errorName(err)});
        };

        self.receiver_thread = std.Thread.spawn(
            .{},
            receiverLoop,
            .{self},
        ) catch return error.ThreadSpawnFailed;
    }

    /// Signals the receiver thread and waits for it to exit.
    pub fn stop(self: *Client) void {
        if (self.receiver_thread) |thread| {
            self.stopping.store(true, .release);
            self.events.close(self.io);
            thread.join();
            self.receiver_thread = null;
        }
    }

    pub fn deinit(self: *Client) void {
        self.stop();

        if (self.tdlib_version) |version| {
            self.allocator.free(version);
            self.tdlib_version = null;
        }

        self.pending_mutex.lockUncancelable(self.io);
        defer self.pending_mutex.unlock(self.io);
        self.pending.deinit(self.allocator);

        self.events.deinit(self.io);
        // Free the library record; the mapped library itself stays until
        // process exit, see `Library.deinit`.
        self.library.deinit();
    }

    /// Sends `request_json` with an automatically assigned `@extra` and
    /// registers it as pending. Returns the assigned extra id.
    pub fn send(
        self: *Client,
        request_json: []const u8,
    ) ClientSendError!u64 {
        const close_index = std.mem.findScalarLast(u8, request_json, '}') orelse
            return error.InvalidRequest;

        const extra = self.next_extra.fetchAdd(1, .monotonic);

        // The format string carries the closing brace literally (`}}`): the
        // prefix excludes it and `,"@extra"` must precede it.
        const request_z = self.allocator.printSentinel(
            "{s},\"@extra\":{d}}}{s}",
            .{
                request_json[0..close_index],
                extra,
                request_json[close_index + 1 ..],
            },
            0,
        ) catch return error.OutOfMemory;
        defer self.allocator.free(request_z);

        self.pending_mutex.lockUncancelable(self.io);
        defer self.pending_mutex.unlock(self.io);
        try self.pending.put(self.allocator, extra, {});

        self.library.symbols.send(self.client_id, request_z.ptr);
        return extra;
    }

    /// Removes one event from the queue and reports its `@extra`, if any.
    /// A matching pending entry is consumed, so `poll` is how requests and
    /// responses get matched. The caller owns `response.json`.
    pub fn poll(self: *Client, timeout_ms: u32) ClientPollError!?Response {
        const bytes = (try self.events.pop(self.io, queue.timeoutMs(timeout_ms))) orelse
            return null;
        errdefer self.allocator.free(bytes);

        const extra = parseEventExtra(self.allocator, bytes) catch
            return error.InvalidEvent;
        if (extra) |matched_extra| {
            self.pending_mutex.lockUncancelable(self.io);
            defer self.pending_mutex.unlock(self.io);
            _ = self.pending.remove(matched_extra);
        }
        return .{ .json = bytes, .extra = extra };
    }
};

/// Receiver thread body: blocks in `td_receive`, copies every event and hands
/// it to the queue. Strings returned by `td_receive` are only valid until the
/// next call in this thread, hence the copy.
fn receiverLoop(self: *Client) void {
    while (!self.stopping.load(.acquire)) {
        const raw = self.library.symbols.receive(self.receive_timeout_seconds) orelse
            continue;

        const copied = self.allocator.dupe(u8, std.mem.span(raw)) catch {
            // Out of memory: stop delivering events instead of spinning.
            std.log.warn("receiver thread stopped: out of memory", .{});
            break;
        };
        self.events.push(self.io, copied) catch {
            self.allocator.free(copied);
            break;
        };
    }
}

test "client matches a response to its request" {
    const allocator = std.testing.allocator;
    const project_root = std.process.currentPathAlloc(
        std.testing.io,
        allocator,
    ) catch return error.SkipZigTest;
    defer allocator.free(project_root);

    const library = Library.init(allocator, .{
        .env_tdlib_path = std.process.Environ.getPosix(
            std.testing.environ,
            "ZIGRAM_TDLIB",
        ),
        .project_root = project_root,
        .home_dir = std.process.Environ.getPosix(
            std.testing.environ,
            "HOME",
        ),
    }) catch |err| switch (err) {
        error.LibraryNotFound, error.MissingSymbols => return error.SkipZigTest,
        else => return err,
    };

    var client: Client = undefined;
    client.init(allocator, std.testing.io, library, .{}) catch |err|
        switch (err) {
            error.ThreadSpawnFailed => return error.SkipZigTest,
            else => return err,
        };
    defer client.deinit();

    const extra = try client.send("{\"@type\":\"getOption\",\"name\":\"version\"}");

    // Cold start of libtdjson can take seconds under machine load, so the
    // budget is generous; the loop returns as soon as the response arrives.
    const response_limit = 60;
    const poll_timeout_ms = 1000;
    var matched: ?[]u8 = null;
    var attempts: usize = 0;
    while (attempts < response_limit) : (attempts += 1) {
        const response = (try client.poll(poll_timeout_ms)) orelse continue;
        if (response.extra) |response_extra| {
            if (response_extra == extra) {
                matched = response.json;
                break;
            }
        }
        allocator.free(response.json);
    }

    const response_json = matched orelse return error.TestUnexpectedResult;
    defer allocator.free(response_json);

    const version = try parseOptionString(allocator, response_json);
    defer allocator.free(version);

    try std.testing.expectEqualStrings(expected_tdlib_version, version);
}

test "live TDLib reports a version" {
    const allocator = std.testing.allocator;
    const project_root = std.process.currentPathAlloc(
        std.testing.io,
        allocator,
    ) catch return error.SkipZigTest;
    defer allocator.free(project_root);

    var library = Library.init(allocator, .{
        .env_tdlib_path = std.process.Environ.getPosix(
            std.testing.environ,
            "ZIGRAM_TDLIB",
        ),
        .project_root = project_root,
        .home_dir = std.process.Environ.getPosix(
            std.testing.environ,
            "HOME",
        ),
    }) catch |err| switch (err) {
        error.LibraryNotFound, error.MissingSymbols => return error.SkipZigTest,
        else => return err,
    };
    defer library.deinit();

    const version = try library.getVersion(allocator);
    defer allocator.free(version);

    try std.testing.expect(version.len > 0);
}
