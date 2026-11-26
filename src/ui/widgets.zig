//! Small reusable pieces of text for the screens.

const std = @import("std");

const gfx = @import("gfx.zig");
const theme = @import("theme/root.zig");

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

/// Draws a message bubble at the cursor and moves to the next line;
/// returns the height it occupied, spacing included.
pub fn bubble(value: []const u8, outgoing: bool) f32 {
    const tokens = theme.current();
    const wrap = @min(tokens.bubble_max_width, gfx.availWidth() - 2 * tokens.padding);
    const size = gfx.textSize(value, wrap);
    const width = size.x + 2 * tokens.padding;
    const height = size.y + 2 * tokens.padding;

    if (outgoing) gfx.setCursorX(@max(0, gfx.availWidth() - width));
    const pos = gfx.cursorScreenPos();
    const color = if (outgoing) tokens.palette.accent else tokens.palette.surface;
    gfx.rectFilled(pos.x, pos.y, pos.x + width, pos.y + height, color, tokens.rounding);
    gfx.textAt(pos.x + tokens.padding, pos.y + tokens.padding, value);

    const line = height + tokens.spacing.y;
    gfx.dummy(line);
    return line;
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
