//! Starting the TDLib client from the configuration.

const std = @import("std");

const zigram = @import("zigram");

const td = zigram.td;

const config = @import("config.zig");
const log = @import("log.zig");

const Allocator = std.mem.Allocator;

/// Loads the library and starts the client; raises the TDLib log verbosity
/// when debug output is enabled. The caller owns the returned client.
pub fn start(
    allocator: Allocator,
    io: std.Io,
    logger: log.Logger,
    loaded: config.Config,
) !*td.Client {
    const library = try td.Library.init(allocator, .{
        .tdlib_path = loaded.tdlib_path,
        .project_root = std.process.currentPathAlloc(io, allocator) catch null,
        .executable_dir = try config.executableDir(io, allocator),
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
