//! The search order of `libtdjson.so`.
//!
//! Builds the ordered list of paths the runtime loader tries: config,
//! environment, `vendor/tdlib/` next to the project and the executable,
//! `~/.local/share/zigram/`, then the system loader.

const std = @import("std");

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
