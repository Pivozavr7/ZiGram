//! Theme tokens: the colors and sizes every part of the interface reads.
//!
//! Nothing in `ui/` may hardcode a color or a size; it asks the tokens
//! instead. The tokens are plain data, so a theme file is a `.zon` document
//! of the same shape (see `loader.zig`).

const std = @import("std");

/// A color in the float form the graphics shim uses.
pub const Color = extern struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,
};

/// A two dimensional size in pixels.
pub const Size = extern struct {
    x: f32,
    y: f32,
};

/// The colors of a theme.
pub const Palette = extern struct {
    /// The clear color behind the windows.
    background: Color,
    /// The background of windows and child regions.
    surface: Color,
    text: Color,
    text_disabled: Color,
    /// The color of a line that reports a problem.
    error_color: Color,
    /// The base color of buttons, selections and highlights.
    accent: Color,
};

/// A complete theme. The field order matches `zig_gfx_theme` in
/// `gfx_shim.h`: the shim receives this struct as is, so change both
/// together.
pub const Tokens = extern struct {
    palette: Palette,
    /// The distance between two consecutive items.
    spacing: Size = .{ .x = 8, .y = 4 },
    /// The rounding of frames, grabs and buttons, in pixels.
    rounding: f32 = 3,
    /// The padding inside windows, in pixels.
    padding: f32 = 8,
    /// The base font size in pixels, before the display scale.
    font_size: f32 = 13,
    /// The width of the chat list panel.
    panel_width: f32 = 280,
    /// The height of the panels of the client view.
    panel_height: f32 = 460,
    /// The height of the message composer.
    composer_height: f32 = 60,
};

test "a token document carries a color and a size" {
    const testing = std.testing;
    const tokens: Tokens = .{
        .palette = .{
            .background = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
            .surface = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
            .text = .{ .r = 1, .g = 1, .b = 1, .a = 1 },
            .text_disabled = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
            .error_color = .{ .r = 1, .g = 0, .b = 0, .a = 1 },
            .accent = .{ .r = 0, .g = 0, .b = 1, .a = 1 },
        },
        .spacing = .{ .x = 8, .y = 4 },
    };

    try testing.expectEqual(@as(f32, 8), tokens.spacing.x);
    try testing.expectEqual(@as(f32, 13), tokens.font_size);
    try testing.expectEqual(@as(f32, 460), tokens.panel_height);
}
