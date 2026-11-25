//! Locate the system fonts the UI draws with.

const std = @import("std");

/// Base font: Latin and Cyrillic.
const base_candidates = [_][*:0]const u8{
    "/usr/share/fonts/noto/NotoSans-Regular.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/dejavu/DejaVuSans.ttf",
};

/// CJK face: a collection (.ttc); the shim takes the first face.
const cjk_candidates = [_][*:0]const u8{
    "/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
};

/// Color emoji: a CBDT bitmap font with a single strike.
const emoji_candidates = [_][*:0]const u8{
    "/usr/share/fonts/noto/NotoColorEmoji.ttf",
    "/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf",
};

/// Font files for the atlas; `null` means the source is skipped.
/// The layout matches `zig_gfx_fonts` in gfx_shim.h; change both together.
pub const Fonts = extern struct {
    base: ?[*:0]const u8 = null,
    cjk: ?[*:0]const u8 = null,
    emoji: ?[*:0]const u8 = null,
};

/// The first existing candidate of each group.
pub fn find(io: std.Io) Fonts {
    return .{
        .base = first(io, &base_candidates),
        .cjk = first(io, &cjk_candidates),
        .emoji = first(io, &emoji_candidates),
    };
}

fn first(io: std.Io, candidates: []const [*:0]const u8) ?[*:0]const u8 {
    for (candidates) |path| {
        std.Io.Dir.accessAbsolute(io, std.mem.span(path), .{}) catch continue;
        return path;
    }
    return null;
}

test "first returns null when no candidate exists" {
    const missing = [_][*:0]const u8{
        "/nonexistent/zigram/font-a.ttf",
        "/nonexistent/zigram/font-b.ttf",
    };
    try std.testing.expect(first(std.testing.io, &missing) == null);
}

test "first returns the first existing candidate" {
    const paths = [_][*:0]const u8{ "/nonexistent/zigram/none.ttf", "/" };
    try std.testing.expect(first(std.testing.io, &paths) != null);
}
