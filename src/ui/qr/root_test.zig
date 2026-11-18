//! End-to-end tests of the encoder: structural invariants of the produced
//! matrices and golden matrices verified against the reference encoder.

const std = @import("std");

const qr = @import("root.zig");

const testing = std.testing;

test "a small payload produces the smallest version" {
    var code = try qr.encode(testing.allocator, "hello", .medium);
    defer code.deinit();

    try testing.expectEqual(@as(u8, 1), code.version);
    try testing.expectEqual(@as(usize, 21), code.size);
    try testing.expectEqual(@as(usize, 21 * 21), code.modules.len);
}

test "the finder and timing patterns are in place" {
    var code = try qr.encode(testing.allocator, "hello", .quartile);
    defer code.deinit();

    // The dark border of the finder pattern covers the corners.
    try testing.expect(code.module(0, 0));
    try testing.expect(code.module(code.size - 1, 0));
    try testing.expect(code.module(0, code.size - 1));

    // The light ring and the dark center of the top left pattern.
    try testing.expect(!code.module(1, 1));
    try testing.expect(code.module(3, 3));

    // The separators around the finder patterns are light.
    try testing.expect(!code.module(7, 0));
    try testing.expect(!code.module(0, 7));

    // The timing patterns alternate between the finder patterns.
    for (8..code.size - 8) |index| {
        try testing.expectEqual(index % 2 == 0, code.module(index, 6));
        try testing.expectEqual(index % 2 == 0, code.module(6, index));
    }

    // The module above the lower left finder pattern is always dark.
    try testing.expect(code.module(8, code.size - 8));
}

test "a payload too long for the highest version is rejected" {
    const too_long: [1300]u8 = @splat('a');
    try testing.expectError(error.PayloadTooLarge, qr.encode(testing.allocator, &too_long, .high));

    // The same payload fits with a weaker error correction level.
    var code = try qr.encode(testing.allocator, &too_long, .low);
    defer code.deinit();
    try testing.expectEqual(@as(u8, 26), code.version);
}

test "the same payload encodes to the same matrix" {
    var first = try qr.encode(testing.allocator, "https://telegram.org", .medium);
    defer first.deinit();
    var second = try qr.encode(testing.allocator, "https://telegram.org", .medium);
    defer second.deinit();

    try testing.expectEqualSlices(bool, first.modules, second.modules);
}

/// The matrix of "hello" at medium, produced by the reference encoder.
const golden_hello = [_][]const u8{
    "111111100110001111111",
    "100000101100001000001",
    "101110100101101011101",
    "101110100011001011101",
    "101110101100101011101",
    "100000100000101000001",
    "111111101010101111111",
    "000000000011100000000",
    "101010100101000010010",
    "001011000010001000011",
    "010100101110100011111",
    "110010000000001000010",
    "011010110010101010000",
    "000000001111010100111",
    "111111100011011100111",
    "100000100011110110000",
    "101110101011011100011",
    "101110100100001100110",
    "101110101110100010101",
    "100000100100001010010",
    "111111101110101100011",
};

test "the matrix of a small payload matches the reference" {
    var code = try qr.encode(testing.allocator, "hello", .medium);
    defer code.deinit();

    try testing.expectEqual(@as(usize, golden_hello.len), code.size);
    for (golden_hello, 0..) |row, y| {
        for (row, 0..) |char, x| {
            try testing.expectEqual(char == '1', code.module(x, y));
        }
    }
}

/// Hashes the modules the way the golden checks below do: the FNV-1a of the
/// dark bits, row by row.
fn moduleDigest(modules: []const bool) u64 {
    var hash: u64 = 0xcbf29ce484222325;
    for (modules) |dark| {
        hash ^= @intFromBool(dark);
        hash = hash *% 0x100000001b3;
    }
    return hash;
}

/// Repeats the pattern of the golden checks: 'a' plus the alphabet.
fn alphabetPayload(comptime length: usize) [length]u8 {
    var payload: [length]u8 = undefined;
    for (&payload, 0..) |*byte, index| byte.* = 'a' + @as(u8, @intCast(index % 26));
    return payload;
}

test "a version fifteen code matches the reference digest" {
    const payload = alphabetPayload(500);

    var code = try qr.encode(testing.allocator, &payload, .low);
    defer code.deinit();

    try testing.expectEqual(@as(u8, 15), code.version);
    try testing.expectEqual(@as(u64, 0xdf2d1ced6231d107), moduleDigest(code.modules));
}

test "the largest code matches the reference digest" {
    const payload = alphabetPayload(2953);

    var code = try qr.encode(testing.allocator, &payload, .low);
    defer code.deinit();

    try testing.expectEqual(@as(u8, 40), code.version);
    try testing.expectEqual(@as(u64, 0xae99baaba8ed7edb), moduleDigest(code.modules));
}
