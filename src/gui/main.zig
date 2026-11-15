//! zigram-gui: native Telegram client UI.
//!
//! MVP 1 skeleton: an SDL3 GPU window rendering an ImGui frame. The screen
//! currently shows the connected TDLib version; the login flow lands next.

const std = @import("std");
const zigram = @import("zigram");

const Event = enum(c_int) {
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
extern fn zig_gfx_text(text: [*:0]const u8) void;
extern fn zig_gfx_text_disabled(text: [*:0]const u8) void;
extern fn zig_gfx_text_error(text: [*:0]const u8) void;
extern fn zig_gfx_separator() void;
extern fn zig_gfx_button(label: [*:0]const u8) bool;
extern fn zig_gfx_input_text(label: [*:0]const u8, buf: [*]u8, size: c_uint) bool;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;

    const window_title = try arena.printSentinel(
        "ZiGram {s}",
        .{zigram.version},
        0,
    );

    if (!zig_gfx_init(window_title.ptr, 420, 360)) {
        var error_buf: [512]u8 = undefined;
        const detail = if (zig_gfx_get_error(&error_buf, error_buf.len))
            error_buf[0..std.mem.sliceTo(&error_buf, 0).len]
        else
            "unknown error";
        var stderr_buffer: [1024]u8 = undefined;
        var stderr_writer: std.Io.File.Writer = .init(.stderr(), init.io, &stderr_buffer);
        try stderr_writer.interface.print(
            "error: failed to initialize the GUI: {s}\n",
            .{detail},
        );
        try stderr_writer.interface.flush();
        std.process.exit(1);
    }
    defer zig_gfx_quit();

    var status_buf: [256]u8 = undefined;
    var status: [*:0]const u8 = "starting";

    var frame: u64 = 0;
    while (true) : (frame += 1) {
        var event = zig_gfx_poll_event();
        while (event != .none) {
            if (event == .quit or event == .window_close) {
                return;
            }
            event = zig_gfx_poll_event();
        }

        if (zig_gfx_minimized()) {
            zig_gfx_delay(10);
            continue;
        }

        zig_gfx_new_frame();

        zig_gfx_set_next_window_pos(24, 24);
        zig_gfx_set_next_window_size(380, 280);
        if (zig_gfx_begin("ZiGram")) {
            if (frame == 0) {
                // Query the TDLib version once, off the hot path.
                status = loadStatus(io, arena, &status_buf) catch "TDLib not loaded";
            }
            zig_gfx_text(status);
            zig_gfx_separator();
            zig_gfx_text_disabled("login screen lands here");
            if (zig_gfx_button("Quit")) {
                return;
            }
        }
        zig_gfx_end();

        zig_gfx_render(0.09, 0.09, 0.11, 1.0);
    }
}

/// Loads the TDLib library through the core and formats the status line.
/// Owns a temporary `Library` for the lifetime of the returned string.
fn loadStatus(
    io: std.Io,
    arena: std.mem.Allocator,
    buf: *[256]u8,
) ![*:0]const u8 {
    const executable_dir = try executableDir(io, arena);
    var library = try zigram.td.Library.init(arena, .{
        .project_root = projectRoot(io, arena) catch null,
        .executable_dir = executable_dir,
        .home_dir = null,
    });
    _ = &library;

    const version = try library.getVersion(arena);
    const text = try std.fmt.bufPrint(buf, "TDLib {s} connected", .{version});
    buf[text.len] = 0;
    return buf[0..text.len :0];
}

fn projectRoot(io: std.Io, arena: std.mem.Allocator) ![]u8 {
    return std.process.currentPathAlloc(io, arena);
}

fn executableDir(io: std.Io, arena: std.mem.Allocator) !?[]u8 {
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = std.Io.Dir.readLinkAbsolute(io, "/proc/self/exe", &buffer) catch return null;
    const dir = std.Io.Dir.path.dirname(buffer[0..length]) orelse return null;
    return try arena.dupe(u8, dir);
}
