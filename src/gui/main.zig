//! zigram-gui: native Telegram client UI.
//!
//! This file owns the window and the frame loop. The login flow and the
//! client view are screens in `ui/screens/`, the state and the commands live
//! in `app/`, the Telegram logic in `core/`.

const std = @import("std");

const zigram = @import("zigram");
const zigram_app = @import("zigram_app");
const zigram_ui = @import("zigram_ui");

const gfx = zigram_ui.gfx;
const widgets = zigram_ui.widgets;

const Login = zigram_ui.screens.login.Login;
const ChatList = zigram_ui.screens.chat_list.ChatList;

const window_width: c_int = 760;
const window_height: c_int = 600;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    var session = try zigram_app.session.Session.init(
        init.gpa,
        init.io,
        .{ .enabled = zigram_app.log.enabledFor(init.environ_map) },
        init.environ_map,
    );
    defer session.deinit();

    const window_title = try arena.printSentinel("ZiGram {s}", .{zigram.version}, 0);
    if (!gfx.init(window_title.ptr, window_width, window_height)) {
        try reportStartupError(init.io);
        std.process.exit(1);
    }
    defer gfx.quit();

    var login_screen = Login{};
    var chat_screen = ChatList{};

    var frame_arena = std.heap.ArenaAllocator.init(init.gpa);
    defer frame_arena.deinit();

    while (true) {
        if (pollQuitEvent()) return;
        if (gfx.minimized()) {
            gfx.delay(10);
            continue;
        }

        try session.drain();
        if (drawFrame(&session, &login_screen, &chat_screen, &frame_arena)) return;
    }
}

/// Draws one frame; reports whether the user asked to quit.
fn drawFrame(
    session: *zigram_app.session.Session,
    login_screen: *Login,
    chat_screen: *ChatList,
    frame_arena: *std.heap.ArenaAllocator,
) bool {
    gfx.newFrame();
    _ = frame_arena.reset(.retain_capacity);
    const scratch = frame_arena.allocator();

    gfx.setNextWindowPos(24, 24);
    gfx.setNextWindowSize(window_width, window_height);
    if (gfx.begin("ZiGram")) {
        if (session.status) |text| {
            widgets.errorText(text);
            gfx.separator();
        }
        if (session.currentScreen() == .ready) {
            if (chat_screen.draw(session, scratch) == .quit) return true;
        } else if (login_screen.draw(session) == .quit) {
            return true;
        }
    }
    gfx.end();
    gfx.render(0.09, 0.09, 0.11, 1.0);
    return false;
}

/// Reports whether the window was closed.
fn pollQuitEvent() bool {
    var event = gfx.pollEvent();
    while (event != .none) {
        if (event == .quit or event == .window_close) return true;
        event = gfx.pollEvent();
    }
    return false;
}

/// Writes the reason of a failed window creation to stderr.
fn reportStartupError(io: std.Io) !void {
    var error_buf: [512]u8 = undefined;
    const detail = if (gfx.getError(&error_buf))
        error_buf[0..std.mem.sliceTo(&error_buf, 0).len]
    else
        "unknown error";
    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer: std.Io.File.Writer = .init(.stderr(), io, &stderr_buffer);
    try stderr_writer.interface.print(
        "error: failed to initialize the GUI: {s}\n",
        .{detail},
    );
    try stderr_writer.interface.flush();
}
