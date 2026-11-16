//! Configuration: `~/.config/zigram/config.zon` and startup diagnostics.

const std = @import("std");

const Allocator = std.mem.Allocator;

/// Credentials and paths of the application.
pub const Config = struct {
    api_id: u32,
    api_hash: []const u8,
    /// Optional override for the libtdjson.so location.
    tdlib_path: ?[]const u8 = null,
};

pub const LoadError = error{
    HomeNotSet,
    ConfigMissing,
    ConfigInvalid,
    ConfigIncomplete,
} || Allocator.Error || std.Io.Dir.ReadFileAllocError || error{ParseZon};

/// Path of the configuration file inside the home directory.
pub fn configPath(allocator: Allocator, home: []const u8) Allocator.Error![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "{s}/.config/zigram/config.zon",
        .{home},
    );
}

/// Loads the configuration file. The caller owns the returned slices.
pub fn load(
    allocator: Allocator,
    io: std.Io,
    home: []const u8,
) LoadError!Config {
    const path = try configPath(allocator, home);
    defer allocator.free(path);

    const config_zon = std.Io.Dir.cwd().readFileAllocOptions(
        io,
        path,
        allocator,
        std.Io.Limit.limited(64 * 1024),
        .of(u8),
        0,
    ) catch |err| switch (err) {
        error.FileNotFound => return error.ConfigMissing,
        else => return err,
    };
    defer allocator.free(config_zon);

    var diagnostics: std.zon.parse.Diagnostics = undefined;
    const config = std.zon.parse.fromSlice(Config, .{
        .gpa = allocator,
        .arena = allocator,
        .source = config_zon,
        .diagnostics = &diagnostics,
    }) catch |err| switch (err) {
        error.ParseZon => {
            std.debug.print(
                "config.zon could not be parsed:\n{f}",
                .{diagnostics.fmt("config.zon")},
            );
            return error.ConfigInvalid;
        },
        else => return err,
    };

    if (config.api_id == 0 or config.api_hash.len == 0) {
        return error.ConfigIncomplete;
    }
    return config;
}

/// Explains a startup failure in a few words the user can act on.
pub fn describeError(
    allocator: Allocator,
    err: anyerror,
) Allocator.Error![]u8 {
    return switch (err) {
        error.HomeNotSet => try allocator.dupe(u8, "$HOME is not set"),
        error.ConfigMissing => try allocator.dupe(u8,
            \\No configuration found.
            \\Create ~/.config/zigram/config.zon with your credentials:
            \\.{
            \\  .api_id = 12345,
            \\  .api_hash = "your-api-hash",
            \\}
            \\api_id/api_hash come from https://my.telegram.org.
        ),
        error.ConfigIncomplete, error.ConfigProblem => try allocator.dupe(u8,
            \\config.zon must define a non-zero api_id and a non-empty
            \\api_hash. See ~/.config/zigram/config.zon.
        ),
        error.LibraryNotFound => try allocator.dupe(u8,
            \\libtdjson.so not found.
            \\Run `bash scripts/fetch-tdlib.sh` or set tdlib_path in
            \\config.zon.
        ),
        error.MissingSymbols => try allocator.dupe(u8,
            \\libtdjson.so was found but does not export the required
            \\td_* symbols. Check the tdlib_path setting.
        ),
        else => try std.fmt.allocPrint(
            allocator,
            "startup failed: {s}",
            .{@errorName(err)},
        ),
    };
}

/// Directory of the running executable; used to find `libtdjson.so`.
pub fn executableDir(io: std.Io, allocator: Allocator) Allocator.Error!?[]u8 {
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = std.Io.Dir.readLinkAbsolute(io, "/proc/self/exe", &buffer) catch return null;
    const dir = std.Io.Dir.path.dirname(buffer[0..length]) orelse return null;
    return try allocator.dupe(u8, dir);
}

test "the config path points into the home directory" {
    const path = try configPath(std.testing.allocator, "/home/user");
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings(
        "/home/user/.config/zigram/config.zon",
        path,
    );
}

test "a missing configuration is explained" {
    const text = try describeError(std.testing.allocator, error.ConfigMissing);
    defer std.testing.allocator.free(text);

    try std.testing.expect(std.mem.indexOf(u8, text, "config.zon") != null);
}

test "an incomplete configuration is explained" {
    const text = try describeError(std.testing.allocator, error.ConfigIncomplete);
    defer std.testing.allocator.free(text);

    try std.testing.expect(std.mem.indexOf(u8, text, "api_id") != null);
}
