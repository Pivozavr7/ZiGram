//! zigram-cli: headless entry point for exercising the ZiGram core.

const std = @import("std");
const zigram = @import("zigram");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    if (args.len < 2) {
        try printUsage(init);
        return;
    }

    const command = args[1];
    if (std.mem.eql(u8, command, "version")) {
        try runVersion(init, arena);
        return;
    }
    if (std.mem.eql(u8, command, "help") or
        std.mem.eql(u8, command, "--help") or
        std.mem.eql(u8, command, "-h"))
    {
        try printUsage(init);
        return;
    }

    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer: std.Io.File.Writer = .init(.stderr(), init.io, &stderr_buffer);
    const stderr = &stderr_writer.interface;

    try stderr.print("error: unknown command: {s}\n", .{command});
    try stderr.writeAll("run `zigram-cli --help` for usage\n");
    try stderr.flush();
    std.process.exit(2);
}

fn printUsage(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.writeAll(
        \\usage: zigram-cli <command>
        \\
        \\commands:
        \\  version   print the loaded TDLib version
        \\
    );
    try stdout.flush();
}

fn runVersion(init: std.process.Init, arena: std.mem.Allocator) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer: std.Io.File.Writer = .init(.stderr(), init.io, &stderr_buffer);
    const stderr = &stderr_writer.interface;

    const project_root = std.process.currentPathAlloc(init.io, arena) catch null;
    const executable_dir = executableDirAlloc(init.io, arena) catch null;

    var library = zigram.td.Library.init(arena, .{
        .env_tdlib_path = init.environ_map.get("ZIGRAM_TDLIB"),
        .project_root = project_root,
        .executable_dir = executable_dir,
        .home_dir = init.environ_map.get("HOME"),
    }) catch |err| {
        switch (err) {
            error.LibraryNotFound => {
                try stderr.writeAll("error: libtdjson.so not found\n");
                try stderr.writeAll(
                    "hint: run `bash scripts/fetch-tdlib.sh` or set ZIGRAM_TDLIB\n",
                );
            },
            error.MissingSymbols => {
                try stderr.writeAll(
                    "error: libtdjson.so was found but lacks the required td_* symbols\n",
                );
            },
            else => return err,
        }
        try stderr.flush();
        std.process.exit(1);
    };
    defer library.deinit();

    const tdlib_version = library.getVersion(arena) catch |err| {
        try stderr.print(
            "error: getOption(version) failed: {s}\n",
            .{@errorName(err)},
        );
        try stderr.flush();
        std.process.exit(1);
    };

    try stdout.print("TDLib {s}\n", .{tdlib_version});
    try stdout.flush();

    if (!std.mem.eql(u8, tdlib_version, zigram.td.expected_tdlib_version)) {
        try stderr.print(
            "warning: ZiGram expects TDLib {s}, got {s}\n",
            .{ zigram.td.expected_tdlib_version, tdlib_version },
        );
        try stderr.flush();
    }
}

/// Returns the directory of the running executable on Linux, or null when it
/// cannot be determined. Used only for the `vendor/` fallback.
fn executableDirAlloc(io: std.Io, allocator: std.mem.Allocator) !?[]u8 {
    if (@import("builtin").target.os.tag != .linux) return null;

    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = std.Io.Dir.readLinkAbsolute(
        io,
        "/proc/self/exe",
        &buffer,
    ) catch return null;

    const dir = std.Io.Dir.path.dirname(buffer[0..length]) orelse return null;
    return try allocator.dupe(u8, dir);
}

test "cli module builds" {
    try std.testing.expect(zigram.version.len > 0);
}
