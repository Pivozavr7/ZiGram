//! Shared helpers for building TDLib request JSON.
//!
//! TDLib request types and some field names start with `@`, and Zig
//! identifiers cannot contain `@`, so requests are assembled by hand instead
//! of through `std.json.Stringify.valueAlloc`.

const std = @import("std");

const Allocator = std.mem.Allocator;

/// A single request field.
pub const Field = struct {
    name: []const u8,
    value: FieldValue,
};

/// The value of a request field.
pub const FieldValue = union(enum) {
    string: []const u8,
    int: i64,
    boolean: bool,
    /// Raw JSON written as is; the caller guarantees that it is valid.
    json: []const u8,
};

pub const Error = Allocator.Error || error{WriteFailed};

/// Builds `{"@type":<type_name>,<field>,...}`. The caller owns the result.
pub fn build(
    allocator: Allocator,
    type_name: []const u8,
    fields: []const Field,
) Error![]u8 {
    var aw: std.Io.Writer.Allocating = try .initCapacity(allocator, 128);
    errdefer aw.deinit();
    const writer = &aw.writer;

    try writer.writeAll("{\"@type\":");
    try std.json.Stringify.encodeJsonString(type_name, .{}, writer);
    for (fields) |field| {
        try writer.writeAll(",");
        try std.json.Stringify.encodeJsonString(field.name, .{}, writer);
        try writer.writeAll(":");
        switch (field.value) {
            .string => |string| try std.json.Stringify.encodeJsonString(string, .{}, writer),
            .int => |int| try writer.print("{d}", .{int}),
            .boolean => |boolean| try writer.writeAll(if (boolean) "true" else "false"),
            .json => |json| try writer.writeAll(json),
        }
    }
    try writer.writeAll("}");
    return aw.toOwnedSlice();
}

/// Writes a JSON string literal (with quotes) into `writer`.
pub fn writeJsonString(
    writer: *std.Io.Writer,
    text: []const u8,
) Error!void {
    try std.json.Stringify.encodeJsonString(text, .{}, writer);
}

test "build encodes fields of every kind" {
    const json = try build(std.testing.allocator, "someRequest", &.{
        .{ .name = "text", .value = .{ .string = "hi \"there\"" } },
        .{ .name = "number", .value = .{ .int = 42 } },
        .{ .name = "flag", .value = .{ .boolean = true } },
        .{ .name = "nested", .value = .{ .json = "{\"@type\":\"chatListMain\"}" } },
    });
    defer std.testing.allocator.free(json);

    try std.testing.expectEqualStrings(
        "{\"@type\":\"someRequest\",\"text\":\"hi \\\"there\\\"\",\"number\":42,\"flag\":true,\"nested\":{\"@type\":\"chatListMain\"}}",
        json,
    );
}

test "build encodes a request without fields" {
    const json = try build(std.testing.allocator, "emptyRequest", &.{});
    defer std.testing.allocator.free(json);

    try std.testing.expectEqualStrings("{\"@type\":\"emptyRequest\"}", json);
}
