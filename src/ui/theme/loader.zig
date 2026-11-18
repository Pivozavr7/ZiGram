//! Loading a theme from a `.zon` document.

const std = @import("std");

const tokens = @import("tokens.zig");

pub const LoadError = error{ParseZon} || std.mem.Allocator.Error;

/// Parses `source`, a `.zon` document shaped like `tokens.Tokens`. Unknown
/// fields are ignored, so an older build still reads a newer theme file.
/// The tokens own no memory, but the parse errors live in `arena`, so it
/// has to outlive `diagnostics`, which describes them on
/// `error.ParseZon`.
pub fn parse(
    arena: std.mem.Allocator,
    source: [:0]const u8,
    diagnostics: *std.zon.parse.Diagnostics,
) LoadError!tokens.Tokens {
    // An arena serves both roles: the parser never frees, and the tokens
    // it returns hold no pointers into the arena.
    return try std.zon.parse.fromSlice(tokens.Tokens, .{
        .gpa = arena,
        .arena = arena,
        .source = source,
        .diagnostics = diagnostics,
        .ignore_unknown_fields = true,
    });
}

test "a complete document becomes tokens" {
    const testing = std.testing;
    const source: [:0]const u8 =
        \\.{
        \\    .palette = .{
        \\        .background = .{ .r = 0.1, .g = 0.1, .b = 0.12, .a = 1 },
        \\        .surface = .{ .r = 0.2, .g = 0.2, .b = 0.2, .a = 1 },
        \\        .text = .{ .r = 1, .g = 1, .b = 1, .a = 1 },
        \\        .text_disabled = .{ .r = 0.5, .g = 0.5, .b = 0.5, .a = 1 },
        \\        .error_color = .{ .r = 1, .g = 0.4, .b = 0.4, .a = 1 },
        \\        .accent = .{ .r = 0.3, .g = 0.6, .b = 0.9, .a = 1 },
        \\    },
        \\    .spacing = .{ .x = 10, .y = 6 },
        \\    .rounding = 5,
        \\    .padding = 12,
        \\    .font_size = 15,
        \\    .panel_width = 300,
        \\    .panel_height = 500,
        \\    .composer_height = 72,
        \\}
    ;

    var diagnostics: std.zon.parse.Diagnostics = undefined;
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const parsed = try parse(arena_state.allocator(), source, &diagnostics);

    try testing.expectEqual(@as(f32, 5), parsed.rounding);
    try testing.expectEqual(@as(f32, 10), parsed.spacing.x);
    try testing.expectEqual(@as(f32, 72), parsed.composer_height);
    try testing.expectEqual(@as(f32, 0.3), parsed.palette.accent.r);
}

test "omitted fields fall back to the defaults" {
    const testing = std.testing;
    const source: [:0]const u8 =
        \\.{
        \\    .palette = .{
        \\        .background = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
        \\        .surface = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
        \\        .text = .{ .r = 1, .g = 1, .b = 1, .a = 1 },
        \\        .text_disabled = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
        \\        .error_color = .{ .r = 1, .g = 0, .b = 0, .a = 1 },
        \\        .accent = .{ .r = 0, .g = 0, .b = 1, .a = 1 },
        \\    },
        \\}
    ;

    var diagnostics: std.zon.parse.Diagnostics = undefined;
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const parsed = try parse(arena_state.allocator(), source, &diagnostics);
    const builtin = @import("builtin.zig").theme;

    try testing.expectEqual(builtin.spacing.x, parsed.spacing.x);
    try testing.expectEqual(builtin.rounding, parsed.rounding);
    try testing.expectEqual(builtin.panel_height, parsed.panel_height);
}

test "unknown fields are ignored and broken documents are rejected" {
    const testing = std.testing;
    const palette =
        \\.palette = .{
        \\    .background = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
        \\    .surface = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
        \\    .text = .{ .r = 1, .g = 1, .b = 1, .a = 1 },
        \\    .text_disabled = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
        \\    .error_color = .{ .r = 1, .g = 0, .b = 0, .a = 1 },
        \\    .accent = .{ .r = 0, .g = 0, .b = 1, .a = 1 },
        \\},
    ;
    const with_extra = try testing.allocator.printSentinel(
        ".{{ {s} .future_field = 42 }}",
        .{palette},
        0,
    );
    defer testing.allocator.free(with_extra);

    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();

    var diagnostics: std.zon.parse.Diagnostics = undefined;
    const parsed = try parse(arena_state.allocator(), with_extra, &diagnostics);
    try testing.expectEqual(@as(f32, 13), parsed.font_size);

    var broken: std.zon.parse.Diagnostics = undefined;
    try testing.expectError(error.ParseZon, parse(
        arena_state.allocator(),
        ".{ .palette = oops }",
        &broken,
    ));
}
