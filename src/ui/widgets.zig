//! Small reusable pieces of text for the screens.

const std = @import("std");

const gfx = @import("gfx.zig");

/// A normal line of text.
pub fn text(value: []const u8) void {
    gfx.text(value);
}

/// A dimmed line of text for hints and empty lists.
pub fn disabled(value: []const u8) void {
    gfx.textDisabled(value);
}

/// A download progress bar with a percentage overlay.
pub fn progress(fraction: f32) void {
    gfx.progressBar(fraction);
}

/// A line of text that reports a problem.
pub fn errorText(value: []const u8) void {
    gfx.textError(value);
}

/// A dimmed line that starts with "Hint: "; overly long hints are skipped.
pub fn hint(value: []const u8) void {
    var buffer: [192]u8 = undefined;
    const line = std.fmt.bufPrint(&buffer, "Hint: {s}", .{value}) catch return;
    buffer[line.len] = 0;
    gfx.textDisabled(buffer[0..line.len :0]);
}
