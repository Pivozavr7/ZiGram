//! Starting the TDLib client from the configuration.

const std = @import("std");

const zigram = @import("zigram");

const td = zigram.td;

const config = @import("config.zig");
const log = @import("log.zig");

const Allocator = std.mem.Allocator;

/// The directories of the library search, owned while the client starts;
/// `td.Library.init` copies the paths it needs.
const SearchPaths = struct {
    allocator: Allocator,
    /// Sentinel-terminated: `currentPathAlloc` allocates `len + 1` bytes,
    /// so `free` must keep the sentinel to free the full allocation.
    project_root: ?[:0]u8 = null,
    executable_dir: ?[]u8 = null,

    fn init(allocator: Allocator, io: std.Io) !SearchPaths {
        return .{
            .allocator = allocator,
            .project_root = std.process.currentPathAlloc(io, allocator) catch null,
            .executable_dir = try config.executableDir(io, allocator),
        };
    }

    fn deinit(self: *SearchPaths) void {
        if (self.project_root) |path| self.allocator.free(path);
        if (self.executable_dir) |path| self.allocator.free(path);
        self.* = undefined;
    }
};

/// Loads the library and starts the client; raises the TDLib log verbosity
/// when debug output is enabled. The caller owns the returned client.
pub fn start(
    allocator: Allocator,
    io: std.Io,
    logger: log.Logger,
    loaded: config.Config,
) !*td.Client {
    var paths = try SearchPaths.init(allocator, io);
    defer paths.deinit();

    const library = try td.Library.init(allocator, .{
        .tdlib_path = loaded.tdlib_path,
        .project_root = paths.project_root,
        .executable_dir = paths.executable_dir,
        .home_dir = null,
    });

    const client = try allocator.create(td.Client);
    errdefer allocator.destroy(client);
    try client.init(allocator, io, library, .{});

    if (logger.enabled) {
        client.library.setLogVerbosity(allocator, 5) catch {};
    }
    return client;
}
