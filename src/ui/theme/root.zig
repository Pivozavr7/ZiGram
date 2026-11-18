//! The theme: the tokens, the built-in theme and the loader.

const tokens = @import("tokens.zig");

pub const builtin = @import("builtin.zig");
pub const loader = @import("loader.zig");

pub const Color = tokens.Color;
pub const Size = tokens.Size;
pub const Palette = tokens.Palette;
pub const Tokens = tokens.Tokens;

/// The tokens the interface draws with right now. Screens read their
/// colors and sizes from here and never from literals.
const installed: Tokens = builtin.theme;

pub fn current() *const Tokens {
    return &installed;
}

test {
    _ = tokens;
    _ = builtin;
    _ = loader;
}
