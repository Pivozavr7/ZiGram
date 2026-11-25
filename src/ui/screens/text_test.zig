//! The text test screen: every script and feature the font stack must draw.

const gfx = @import("../gfx.zig");
const widgets = @import("../widgets.zig");

/// One line per script plus a field to type into: Latin and Cyrillic from
/// the base font, CJK from the merged collection, emoji as color bitmaps,
/// and an input where IME composition shows up.
pub const TextTest = struct {
    /// Bounded to what a Telegram message may hold, zero-terminated.
    input: [4097]u8 = @splat(0),

    pub fn draw(self: *TextTest) void {
        widgets.text("Latin: The quick brown fox jumps over the lazy dog.");
        widgets.text("Cyrillic: Съешь же ещё этих мягких французских булок.");
        widgets.text("CJK: 你好，世界！ こんにちは、한국어!");
        widgets.text("Emoji: 👋🏽🚀🎉 ❤️ café €100 ½ ×");
        widgets.disabled("Disabled style: a dimmed hint line.");
        widgets.errorText("Error style: failed to fetch messages.");
        gfx.separator();
        widgets.text("Type here: IME, Cyrillic or emoji all land in this field.");
        _ = gfx.inputText("Input", self.input[0..]);
        if (gfx.button("Clear")) @memset(self.input[0..], 0);
    }
};
