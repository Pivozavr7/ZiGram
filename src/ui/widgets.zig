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
    const box = measure(value);
    const tokens = theme.current();

    if (outgoing) gfx.setCursorX(@max(0, gfx.availWidth() - box.width));
    const pos = gfx.cursorScreenPos();
    const color = if (outgoing) tokens.palette.accent else tokens.palette.surface;
    gfx.rectFilled(pos.x, pos.y, pos.x + box.width, pos.y + box.height, color, tokens.rounding);
    gfx.textAt(pos.x + tokens.padding, pos.y + tokens.padding, value);

    gfx.dummy(box.line);
    return box.line;
}

/// The height a bubble would occupy, spacing included; for the height cache
/// of a virtualized message list.
pub fn bubbleHeight(value: []const u8) f32 {
    return measure(value).line;
}

/// The box a bubble wraps its text into.
const Box = struct {
    width: f32,
    height: f32,
    /// The height of the whole line: the box plus the spacing below it.
    line: f32,
};

fn measure(value: []const u8) Box {
    const tokens = theme.current();
    const wrap = @min(tokens.bubble_max_width, gfx.availWidth() - 2 * tokens.padding);
    const size = gfx.textSize(value, wrap);
    return .{
        .width = size.x + 2 * tokens.padding,
        .height = size.y + 2 * tokens.padding,
        .line = size.y + 2 * tokens.padding + tokens.spacing.y,
    };
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
