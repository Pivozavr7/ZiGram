//! Loading `libtdjson.so` and the symbol table of its JSON interface.
//!
//! This file is the only place that opens TDLib with `std.DynLib` and
//! touches its C ABI; callers receive Zig-owned strings and errors.

const std = @import("std");

const td_options = @import("options.zig");
const search = @import("search.zig");

/// TDLib version ZiGram is developed and tested against.
pub const expected_tdlib_version = "1.8.70";

const version_request = "{\"@type\":\"getOption\",\"name\":\"version\"}";

const Source = search.Source;
const SearchOptions = search.SearchOptions;

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
        var candidates = try search.searchCandidatesAlloc(allocator, options);
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
        return td_options.parseOptionString(allocator, response);
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
