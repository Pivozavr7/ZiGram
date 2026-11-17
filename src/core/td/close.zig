//! Graceful shutdown of the TDLib client.
//!
//! TDLib keeps background threads (network, database) alive for as long as
//! a client is open. When the process exits with such a client alive, the
//! static destructors of TDLib run before those threads stop, and TDLib
//! aborts the process with a `MultiSequenceDispatcher` assertion.
//!
//! The supported way out is the `close` request: TDLib answers it with the
//! `authorizationStateClosed` authorization state and only then releases the
//! client. The client is gone when that answer arrives, so the process may
//! exit safely afterwards.

const std = @import("std");

const auth = @import("../auth/state.zig");
const client_mod = @import("client.zig");
const library_mod = @import("library.zig");
const options = @import("options.zig");

const Client = client_mod.Client;
const Library = library_mod.Library;

/// The request that asks TDLib to close the client.
const close_request = "{\"@type\":\"close\"}";

/// How long one poll waits for the next event.
const poll_slice_ms: u32 = 100;

pub const CloseError = error{
    /// The `close` request could not be sent.
    SendFailed,
    /// TDLib did not confirm the shutdown in time.
    Timeout,
} || std.mem.Allocator.Error;

/// Closes the client and waits until TDLib confirms the shutdown.
///
/// The caller still owns the client and has to `deinit` it afterwards; this
/// function only performs the protocol handshake.
pub fn closeClient(
    client: *Client,
    allocator: std.mem.Allocator,
    timeout_ms: u32,
) CloseError!void {
    _ = client.send(close_request) catch return error.SendFailed;

    var remaining = timeout_ms;
    while (remaining > 0) {
        const slice = @min(remaining, poll_slice_ms);
        remaining -= slice;

        const response = (client.poll(slice) catch break) orelse continue;
        const closed = options.isAuthorizationClosed(allocator, response.json);
        client.allocator.free(response.json);
        if (closed) return;
    }
    return error.Timeout;
}

test "a client with running TDLib threads closes gracefully" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    const project_root = std.process.currentPathAlloc(io, allocator) catch
        return error.SkipZigTest;
    defer allocator.free(project_root);

    const library = Library.init(allocator, .{
        .env_tdlib_path = std.process.Environ.getPosix(
            std.testing.environ,
            "ZIGRAM_TDLIB",
        ),
        .project_root = project_root,
        .home_dir = std.process.Environ.getPosix(
            std.testing.environ,
            "HOME",
        ),
    }) catch |err| switch (err) {
        error.LibraryNotFound, error.MissingSymbols => return error.SkipZigTest,
        else => return err,
    };

    var client: Client = undefined;
    client.init(allocator, io, library, .{}) catch |err| switch (err) {
        error.ThreadSpawnFailed => return error.SkipZigTest,
        else => return err,
    };
    defer client.deinit();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const database_path = try std.fmt.allocPrint(
        allocator,
        ".zig-cache/tmp/{s}/database",
        .{tmp.sub_path},
    );
    defer allocator.free(database_path);
    const files_path = try std.fmt.allocPrint(
        allocator,
        ".zig-cache/tmp/{s}/files",
        .{tmp.sub_path},
    );
    defer allocator.free(files_path);

    // The same request the GUI sends: it makes TDLib start its database and
    // network threads, the ones that used to abort the process at exit.
    const parameters = try std.fmt.allocPrint(
        allocator,
        "{{\"@type\":\"setTdlibParameters\",\"database_directory\":\"{s}\",\"files_directory\":\"{s}\",\"system_language_code\":\"en\",\"device_model\":\"ZiGram\",\"application_version\":\"0.0.0\",\"api_id\":123,\"api_hash\":\"hash\",\"use_message_database\":true,\"use_secret_chats\":false}}",
        .{ database_path, files_path },
    );
    defer allocator.free(parameters);
    _ = try client.send(parameters);

    try expectPhoneNumberState(&client, allocator);

    try closeClient(&client, allocator, 10_000);
}

/// Waits until the client asks for a phone number; that means TDLib is
/// running with its background threads.
fn expectPhoneNumberState(client: *Client, allocator: std.mem.Allocator) !void {
    var remaining: u32 = 30_000;
    while (remaining > 0) : (remaining -= 100) {
        const response = (try client.poll(100)) orelse continue;
        const maybe_update = auth.Update.parse(allocator, response.json) catch {
            client.allocator.free(response.json);
            continue;
        };
        defer client.allocator.free(response.json);

        var update = maybe_update orelse continue;
        defer update.deinit();

        if (update.state == .wait_phone_number) return;
    }
    return error.TestUnexpectedResult;
}
