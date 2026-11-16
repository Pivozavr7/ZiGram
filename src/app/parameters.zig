//! The directories TDLib stores its data in.

const std = @import("std");

const Allocator = std.mem.Allocator;

/// The data directories of the application; TDLib creates them itself, but
/// only when the paths exist.
pub const Paths = struct {
    allocator: Allocator,
    data_dir: []u8,
    files_dir: []u8,

    /// Builds the paths of the data directories.
    pub fn init(allocator: Allocator, home: []const u8) !Paths {
        // TDLib does not expand `~`, so the paths have to be absolute.
        const data_dir = try std.fmt.allocPrint(
            allocator,
            "{s}/.local/share/zigram",
            .{home},
        );
        errdefer allocator.free(data_dir);
        const files_dir = try std.fmt.allocPrint(
            allocator,
            "{s}/.local/share/zigram/files",
            .{home},
        );
        errdefer allocator.free(files_dir);

        return .{
            .allocator = allocator,
            .data_dir = data_dir,
            .files_dir = files_dir,
        };
    }

    /// Creates the directories; TDLib expects them to exist.
    pub fn create(self: *Paths, io: std.Io) !void {
        try createDir(io, self.data_dir);
        try createDir(io, self.files_dir);
    }

    pub fn deinit(self: *Paths) void {
        self.allocator.free(self.data_dir);
        self.allocator.free(self.files_dir);
        self.* = undefined;
    }
};

fn createDir(io: std.Io, path: []const u8) !void {
    std.Io.Dir.cwd().createDirPath(io, path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
}

test "the paths point into the home directory" {
    var paths = try Paths.init(std.testing.allocator, "/home/user");
    defer paths.deinit();

    try std.testing.expectEqualStrings(
        "/home/user/.local/share/zigram",
        paths.data_dir,
    );
    try std.testing.expectEqualStrings(
        "/home/user/.local/share/zigram/files",
        paths.files_dir,
    );
}
