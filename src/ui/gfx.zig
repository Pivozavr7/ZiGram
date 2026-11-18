//! Zig wrappers over the C++ shim that draws with SDL3 and Dear ImGui.
//!
//! Every string that reaches the shim comes with a length: data from TDLib
//! or the config is not null-terminated by contract.

const std = @import("std");

/// What the window system reported since the last poll.
pub const Event = enum(c_int) {
    none = 0,
    quit,
    window_close,
    other,
};

extern fn zig_gfx_init(title: [*:0]const u8, width: c_int, height: c_int) bool;
extern fn zig_gfx_quit() void;
extern fn zig_gfx_get_error(buf: [*]u8, size: c_uint) bool;
extern fn zig_gfx_minimized() bool;
extern fn zig_gfx_delay(ms: c_uint) void;
extern fn zig_gfx_poll_event() Event;
extern fn zig_gfx_new_frame() void;
extern fn zig_gfx_render(r: f32, g: f32, b: f32, a: f32) void;
extern fn zig_gfx_set_next_window_pos(x: f32, y: f32) void;
extern fn zig_gfx_set_next_window_size(w: f32, h: f32) void;
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
extern fn zig_gfx_input_text_multiline(label: [*:0]const u8, buf: [*]u8, size: c_uint) bool;
extern fn zig_gfx_same_line() void;
extern fn zig_gfx_draw_qr(modules: [*]const bool, count: c_int, scale: c_int) bool;

/// Opens the window; returns false when the GPU device is unavailable.
pub fn init(title: [*:0]const u8, width: c_int, height: c_int) bool {
    return zig_gfx_init(title, width, height);
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

pub fn setNextWindowPos(x: f32, y: f32) void {
    zig_gfx_set_next_window_pos(x, y);
}

pub fn setNextWindowSize(w: f32, h: f32) void {
    zig_gfx_set_next_window_size(w, h);
}

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

pub fn inputMultiline(label: [*:0]const u8, buf: []u8) bool {
    return zig_gfx_input_text_multiline(label, buf.ptr, @intCast(buf.len));
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

/// Draws an encoded QR code: `modules` holds `size * size` entries, `true`
/// for the dark ones. A scale of zero lets the shim pick the pixel size that
/// fits the window; returns false when the matrix is empty or unreasonably
/// large.
pub fn qr(modules: []const bool, size: usize, scale: u32) bool {
    if (modules.len == 0 or modules.len != size * size) return false;
    return zig_gfx_draw_qr(modules.ptr, @intCast(size), @intCast(scale));
}
