//! Runtime binding to TDLib's JSON interface (`libtdjson.so`).
//!
//! The library is loaded with `std.DynLib`, so ZiGram builds without TDLib
//! present. This file is the only place that touches TDLib's C ABI; callers
//! receive Zig-owned strings and errors.

const std = @import("std");

/// TDLib version ZiGram is developed and tested against.
pub const expected_tdlib_version = "1.8.70";

const version_request = "{\"@type\":\"getOption\",\"name\":\"version\"}";

/// Where a loaded library came from. The order matches the search order in
/// AGENTS.md.
pub const Source = enum {
    config,
    environment,
    project_vendor,
    executable_vendor,
    user_data,
    system_library,
};

/// One path that may contain `libtdjson.so`.
pub const Candidate = struct {
    source: Source,
    path: []const u8,
};

/// A list of owned candidate paths.
pub const Candidates = struct {
    allocator: std.mem.Allocator,
    items: []Candidate,

    pub fn deinit(self: *Candidates) void {
        for (self.items) |candidate| {
            self.allocator.free(candidate.path);
        }
        self.allocator.free(self.items);
        self.* = undefined;
    }
};

/// Inputs for the library search. A `null` field means "not configured";
/// the corresponding candidate is skipped.
pub const SearchOptions = struct {
    /// `tdlib_path` from the ZiGram config file.
    tdlib_path: ?[]const u8 = null,
    /// `$ZIGRAM_TDLIB`.
    env_tdlib_path: ?[]const u8 = null,
    /// Directory that contains the `vendor/` tree (usually the project root).
    project_root: ?[]const u8 = null,
    /// Directory that contains the running executable.
    executable_dir: ?[]const u8 = null,
    /// User's home directory, used for `~/.local/share/zigram/`.
    home_dir: ?[]const u8 = null,
};

/// Builds the ordered list of paths to try, including the final system
/// fallback. The caller owns the result and must call `deinit`.
pub fn searchCandidatesAlloc(
    allocator: std.mem.Allocator,
    options: SearchOptions,
) std.mem.Allocator.Error!Candidates {
    var list: std.ArrayList(Candidate) = .empty;
    errdefer {
        for (list.items) |candidate| {
            allocator.free(candidate.path);
        }
        list.deinit(allocator);
    }

    if (options.tdlib_path) |path| {
        try appendCandidate(allocator, &list, .config, path);
    }
    if (options.env_tdlib_path) |path| {
        try appendCandidate(allocator, &list, .environment, path);
    }
    if (options.project_root) |root| {
        try appendJoined(
            allocator,
            &list,
            .project_vendor,
            root,
            "vendor/tdlib/libtdjson.so",
        );
    }
    if (options.executable_dir) |dir| {
        try appendJoined(
            allocator,
            &list,
            .executable_vendor,
            dir,
            "vendor/tdlib/libtdjson.so",
        );
    }
    if (options.home_dir) |home| {
        try appendJoined(
            allocator,
            &list,
            .user_data,
            home,
            ".local/share/zigram/libtdjson.so",
        );
    }
    try appendCandidate(allocator, &list, .system_library, "libtdjson.so");

    return .{
        .allocator = allocator,
        .items = try list.toOwnedSlice(allocator),
    };
}

fn appendCandidate(
    allocator: std.mem.Allocator,
    list: *std.ArrayList(Candidate),
    source: Source,
    path: []const u8,
) std.mem.Allocator.Error!void {
    if (path.len == 0) return;

    const owned_path = try allocator.dupe(u8, path);
    errdefer allocator.free(owned_path);
    try list.append(allocator, .{ .source = source, .path = owned_path });
}

fn appendJoined(
    allocator: std.mem.Allocator,
    list: *std.ArrayList(Candidate),
    source: Source,
    base: []const u8,
    relative_path: []const u8,
) std.mem.Allocator.Error!void {
    if (base.len == 0) return;

    const path = try std.Io.Dir.path.join(allocator, &.{ base, relative_path });
    errdefer allocator.free(path);
    try list.append(allocator, .{ .source = source, .path = path });
}

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

pub const VersionError = ExecuteError ||
    std.json.ParseError(std.json.Scanner) ||
    error{ UnexpectedResponse, TdLibError };

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
};

const OptionResponse = struct {
    @"@type": []const u8,
    value: ?[]const u8 = null,
    code: ?i64 = null,
    message: ?[]const u8 = null,
};

/// Extracts `value` from a TDLib `optionValueString` response.
///
/// Unknown fields are ignored on purpose: TDLib adds fields between versions.
pub fn parseOptionString(
    allocator: std.mem.Allocator,
    response_json: []const u8,
) VersionError![]u8 {
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

test "search candidates follow the documented order" {
    var candidates = try searchCandidatesAlloc(std.testing.allocator, .{
        .tdlib_path = "/config/libtdjson.so",
        .env_tdlib_path = "/env/libtdjson.so",
        .project_root = "/project",
        .executable_dir = "/opt/zigram/bin",
        .home_dir = "/home/user",
    });
    defer candidates.deinit();

    try std.testing.expectEqual(@as(usize, 6), candidates.items.len);

    try std.testing.expectEqual(Source.config, candidates.items[0].source);
    try std.testing.expectEqualStrings(
        "/config/libtdjson.so",
        candidates.items[0].path,
    );

    try std.testing.expectEqual(Source.environment, candidates.items[1].source);
    try std.testing.expectEqualStrings(
        "/env/libtdjson.so",
        candidates.items[1].path,
    );

    try std.testing.expectEqual(Source.project_vendor, candidates.items[2].source);
    try std.testing.expectEqualStrings(
        "/project/vendor/tdlib/libtdjson.so",
        candidates.items[2].path,
    );

    try std.testing.expectEqual(Source.executable_vendor, candidates.items[3].source);
    try std.testing.expectEqualStrings(
        "/opt/zigram/bin/vendor/tdlib/libtdjson.so",
        candidates.items[3].path,
    );

    try std.testing.expectEqual(Source.user_data, candidates.items[4].source);
    try std.testing.expectEqualStrings(
        "/home/user/.local/share/zigram/libtdjson.so",
        candidates.items[4].path,
    );

    try std.testing.expectEqual(Source.system_library, candidates.items[5].source);
    try std.testing.expectEqualStrings(
        "libtdjson.so",
        candidates.items[5].path,
    );
}

test "empty search options fall back to the system library" {
    var candidates = try searchCandidatesAlloc(std.testing.allocator, .{});
    defer candidates.deinit();

    try std.testing.expectEqual(@as(usize, 1), candidates.items.len);
    try std.testing.expectEqual(Source.system_library, candidates.items[0].source);
    try std.testing.expectEqualStrings("libtdjson.so", candidates.items[0].path);
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
