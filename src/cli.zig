//! zigram-cli: headless entry point for exercising the ZiGram core.

const std = @import("std");
const zigram = @import("zigram");

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("ZiGram {s}\n", .{zigram.version});
    try stdout.writeAll("The Telegram core is not wired up yet.\n");
    try stdout.flush();
}

test "cli module builds" {
    try std.testing.expect(zigram.version.len > 0);
}
