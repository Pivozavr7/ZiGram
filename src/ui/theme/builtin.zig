//! The built-in dark theme: what the interface uses until a theme file
//! says otherwise. The values match the colors the interface hardcoded
//! before the tokens existed.

const std = @import("std");

const tokens = @import("tokens.zig");

/// The built-in theme.
pub const theme: tokens.Tokens = .{
    .palette = .{
        // The clear color of the frame loop.
        .background = .{ .r = 0.09, .g = 0.09, .b = 0.11, .a = 1 },
        .surface = .{ .r = 0.18, .g = 0.18, .b = 0.18, .a = 1 },
        .text = .{ .r = 1, .g = 1, .b = 1, .a = 1 },
        .text_disabled = .{ .r = 0.58, .g = 0.58, .b = 0.58, .a = 1 },
        .error_color = .{ .r = 1, .g = 0.4, .b = 0.4, .a = 1 },
        .accent = .{ .r = 0.26, .g = 0.59, .b = 0.98, .a = 1 },
    },
};

test "the built-in theme is complete and opaque" {
    const testing = std.testing;
    const colors = [_]tokens.Color{
        theme.palette.background,
        theme.palette.surface,
        theme.palette.text,
        theme.palette.text_disabled,
        theme.palette.error_color,
        theme.palette.accent,
    };
    for (colors) |color| {
        try testing.expectEqual(@as(f32, 1), color.a);
    }

    try testing.expect(theme.rounding > 0);
    try testing.expect(theme.spacing.x > 0 and theme.spacing.y > 0);
    try testing.expect(theme.font_size > 0);
    try testing.expect(theme.panel_width > 0 and theme.panel_height > 0);
    try testing.expect(theme.composer_height > 0);
}
