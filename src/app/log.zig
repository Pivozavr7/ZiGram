//! Debug logging with secret redaction.
//!
//! Debug output is off unless `ZIGRAM_DEBUG` is set. It contains message
//! text and phone numbers by definition, so it must never be left enabled in
//! production logs.

const std = @import("std");

const Allocator = std.mem.Allocator;

pub const Logger = struct {
    /// True when `ZIGRAM_DEBUG` is set to anything but `0` or empty.
    enabled: bool = false,

    /// Logs a raw TDLib event.
    pub fn event(self: Logger, json: []const u8) void {
        if (!self.enabled) return;
        std.debug.print("event: {s}\n", .{json});
    }

    /// Logs an event that failed to parse; the error name only, never the
    /// event content, which may hold private data.
    pub fn unparsable(self: Logger, err: anyerror) void {
        if (!self.enabled) return;
        std.debug.print("unparsable event: {s}\n", .{@errorName(err)});
    }

    /// Logs an outgoing request with the `api_hash` value redacted.
    pub fn request(self: Logger, allocator: Allocator, json: []const u8) void {
        if (!self.enabled) return;
        const redacted = redact(allocator, json) catch {
            std.debug.print("request: {s}\n", .{json});
            return;
        };
        defer allocator.free(redacted);
        std.debug.print("request: {s}\n", .{redacted});
    }
};

/// Returns true when `ZIGRAM_DEBUG` is set to anything but `0` or empty.
pub fn enabledFor(environ: *const std.process.Environ.Map) bool {
    const flag = environ.get("ZIGRAM_DEBUG") orelse return false;
    return flag.len > 0 and !std.mem.eql(u8, flag, "0");
}

/// Returns a copy of `json` with the `api_hash` value replaced by `***`.
pub fn redact(allocator: Allocator, json: []const u8) Allocator.Error![]u8 {
    const marker = "\"api_hash\":\"";
    const field_start = std.mem.indexOf(u8, json, marker) orelse
        return allocator.dupe(u8, json);
    const value_start = field_start + marker.len;
    const value_end = std.mem.indexOfScalarPos(u8, json, value_start, '"') orelse
        return allocator.dupe(u8, json);

    return std.fmt.allocPrint(
        allocator,
        "{s}\"api_hash\":\"***\"{s}",
        .{ json[0..field_start], json[value_end + 1 ..] },
    );
}

test "the api hash is redacted" {
    const json = "{\"@type\":\"setTdlibParameters\",\"api_hash\":\"secret\"}";
    const redacted = try redact(std.testing.allocator, json);
    defer std.testing.allocator.free(redacted);

    try std.testing.expectEqualStrings(
        "{\"@type\":\"setTdlibParameters\",\"api_hash\":\"***\"}",
        redacted,
    );
}

test "a request without an api hash is kept as is" {
    const json = "{\"@type\":\"getOption\"}";
    const redacted = try redact(std.testing.allocator, json);
    defer std.testing.allocator.free(redacted);

    try std.testing.expectEqualStrings(json, redacted);
}

test "debug logging is off without the environment flag" {
    const logger = Logger{};
    try std.testing.expect(!logger.enabled);
}
