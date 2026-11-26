//! Zig wrappers over the C++ shim that draws with SDL3 and Dear ImGui.
//!
//! Every string that reaches the shim comes with a length: data from TDLib
//! or the config is not null-terminated by contract.

const std = @import("std");

const theme = @import("theme/root.zig");
const fonts = @import("fonts.zig");

/// What the window system reported since the last poll.
pub const Event = enum(c_int) {
    none = 0,
    quit,
    window_close,
    other,
};

extern fn zig_gfx_init(
    title: [*:0]const u8,
    width: c_int,
    height: c_int,
    tokens: *const theme.Tokens,
    font_files: *const fonts.Fonts,
) bool;
extern fn zig_gfx_quit() void;
extern fn zig_gfx_get_error(buf: [*]u8, size: c_uint) bool;
extern fn zig_gfx_minimized() bool;
extern fn zig_gfx_delay(ms: c_uint) void;
extern fn zig_gfx_poll_event() Event;
extern fn zig_gfx_new_frame() void;
extern fn zig_gfx_render(r: f32, g: f32, b: f32, a: f32) void;
extern fn zig_gfx_begin(title: [*:0]const u8) bool;
extern fn zig_gfx_end() void;
extern fn zig_gfx_text(text: [*]const u8, size: c_uint) void;
extern fn zig_gfx_text_disabled(text: [*]const u8, size: c_uint) void;
extern fn zig_gfx_text_error(text: [*]const u8, size: c_uint) void;
extern fn zig_gfx_separator() void;
extern fn zig_gfx_button(label: [*:0]const u8) bool;
extern fn zig_gfx_input_text(label: [*:0]const u8, buf: [*]u8, size: c_uint) bool;
extern fn zig_gfx_input_text_password(label: [*:0]const u8, buf: [*]u8, size: c_uint) bool;
extern fn zig_gfx_begin_child(label: [*:0]const u8, size_x: f32, size_y: f32) bool;
extern fn zig_gfx_end_child() void;
extern fn zig_gfx_selectable(label: [*:0]const u8, selected: bool) bool;
extern fn zig_gfx_input_text_multiline(
    label: [*:0]const u8,
    buf: [*]u8,
    size: c_uint,
    height: f32,
) bool;
extern fn zig_gfx_same_line() void;
extern fn zig_gfx_progress_bar(fraction: f32) void;
extern fn zig_gfx_text_size(
    text: [*]const u8,
    size: c_uint,
    wrap_width: f32,
    out_w: *f32,
    out_h: *f32,
) void;
extern fn zig_gfx_rect_filled(
    min_x: f32,
    min_y: f32,
    max_x: f32,
    max_y: f32,
    color: theme.Color,
    rounding: f32,
) void;
extern fn zig_gfx_dummy(height: f32) void;
extern fn zig_gfx_scroll_y() f32;
extern fn zig_gfx_window_height() f32;
extern fn zig_gfx_set_scroll_y(value: f32) void;
extern fn zig_gfx_cursor_screen_pos(out_x: *f32, out_y: *f32) void;
extern fn zig_gfx_avail_width() f32;
extern fn zig_gfx_set_cursor_x(value: f32) void;
extern fn zig_gfx_text_at(x: f32, y: f32, text: [*]const u8, size: c_uint) void;
extern fn zig_gfx_frame_height() f32;
extern fn zig_gfx_draw_qr(modules: [*]const bool, count: c_int, scale: c_int) bool;

/// Opens the window with the current theme and the system fonts; returns
/// false when the GPU device is unavailable.
pub fn init(io: std.Io, title: [*:0]const u8, width: c_int, height: c_int) bool {
    const found = fonts.find(io);
    return zig_gfx_init(title, width, height, theme.current(), &found);
}

pub fn quit() void {
    zig_gfx_quit();
}

/// Reads the error of a failed `init` into `buf`.
pub fn getError(buf: []u8) bool {
    return zig_gfx_get_error(buf.ptr, @intCast(buf.len));
}

pub fn minimized() bool {
    return zig_gfx_minimized();
}

pub fn delay(ms: u32) void {
    zig_gfx_delay(ms);
}

pub fn pollEvent() Event {
    return zig_gfx_poll_event();
}

pub fn newFrame() void {
    zig_gfx_new_frame();
}

pub fn render(r: f32, g: f32, b: f32, a: f32) void {
    zig_gfx_render(r, g, b, a);
}

/// Opens the root window: it fills the whole client area and is not
/// decorated; every screen draws inside it.
pub fn begin(title: [*:0]const u8) bool {
    return zig_gfx_begin(title);
}

pub fn end() void {
    zig_gfx_end();
}

pub fn text(value: []const u8) void {
    zig_gfx_text(value.ptr, @intCast(value.len));
}

pub fn textDisabled(value: []const u8) void {
    zig_gfx_text_disabled(value.ptr, @intCast(value.len));
}

pub fn textError(value: []const u8) void {
    zig_gfx_text_error(value.ptr, @intCast(value.len));
}

pub fn separator() void {
    zig_gfx_separator();
}

pub fn button(label: [*:0]const u8) bool {
    return zig_gfx_button(label);
}

pub fn inputText(label: [*:0]const u8, buf: []u8) bool {
    return zig_gfx_input_text(label, buf.ptr, @intCast(buf.len));
}

pub fn inputPassword(label: [*:0]const u8, buf: []u8) bool {
    return zig_gfx_input_text_password(label, buf.ptr, @intCast(buf.len));
}

/// A multi line input of the given height in pixels.
pub fn inputMultiline(label: [*:0]const u8, buf: []u8, height: f32) bool {
    return zig_gfx_input_text_multiline(label, buf.ptr, @intCast(buf.len), height);
}

pub fn beginChild(label: [*:0]const u8, size_x: f32, size_y: f32) bool {
    return zig_gfx_begin_child(label, size_x, size_y);
}

pub fn endChild() void {
    zig_gfx_end_child();
}

pub fn selectable(label: [*:0]const u8, selected: bool) bool {
    return zig_gfx_selectable(label, selected);
}

pub fn sameLine() void {
    zig_gfx_same_line();
}

/// A progress bar across the remaining width; `fraction` is 0..=1.
pub fn progressBar(fraction: f32) void {
    zig_gfx_progress_bar(fraction);
}

/// The space a text block occupies, wrapped at `wrap_width` pixels; a wrap
/// width below 0 disables wrapping.
pub fn textSize(value: []const u8, wrap_width: f32) theme.Size {
    var width: f32 = 0;
    var height: f32 = 0;
    zig_gfx_text_size(value.ptr, @intCast(value.len), wrap_width, &width, &height);
    return .{ .x = width, .y = height };
}

/// A filled rounded rectangle in window coordinates.
pub fn rectFilled(
    min_x: f32,
    min_y: f32,
    max_x: f32,
    max_y: f32,
    color: theme.Color,
    rounding: f32,
) void {
    zig_gfx_rect_filled(min_x, min_y, max_x, max_y, color, rounding);
}

/// An invisible placeholder that keeps the scroll range of a virtualized
/// list correct.
pub fn dummy(height: f32) void {
    zig_gfx_dummy(height);
}

/// Vertical scroll of the current window.
pub fn scrollY() f32 {
    return zig_gfx_scroll_y();
}

/// Inner height of the current window.
pub fn windowHeight() f32 {
    return zig_gfx_window_height();
}

/// Moves the vertical scroll of the current window.
pub fn setScrollY(value: f32) void {
    zig_gfx_set_scroll_y(value);
}

/// Where the cursor stands in screen coordinates.
pub fn cursorScreenPos() theme.Size {
    var x: f32 = 0;
    var y: f32 = 0;
    zig_gfx_cursor_screen_pos(&x, &y);
    return .{ .x = x, .y = y };
}

/// Horizontal room left in the current region.
pub fn availWidth() f32 {
    return zig_gfx_avail_width();
}

/// Moves the horizontal cursor inside the current region.
pub fn setCursorX(value: f32) void {
    zig_gfx_set_cursor_x(value);
}

/// Draws text at a screen position without taking layout space.
pub fn textAt(x: f32, y: f32, value: []const u8) void {
    zig_gfx_text_at(x, y, value.ptr, @intCast(value.len));
}

/// The height in pixels of one framed widget: buttons and inputs. Used to
/// reserve a row at the bottom of a pane.
pub fn frameHeight() f32 {
    return zig_gfx_frame_height();
}

/// Draws an encoded QR code: `modules` holds `size * size` entries, `true`
/// for the dark ones. A scale of zero lets the shim pick the pixel size that
/// fits the window; returns false when the matrix is empty or unreasonably
/// large.
pub fn qr(modules: []const bool, size: usize, scale: u32) bool {
    if (modules.len == 0 or modules.len != size * size) return false;
    return zig_gfx_draw_qr(modules.ptr, @intCast(size), @intCast(scale));
}
