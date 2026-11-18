//! The data part of a QR code: the bit stream, the error correction codewords
//! and the interleaving of the blocks.
//!
//! Only byte mode is implemented: it carries any UTF-8 text, which is what
//! the Telegram login link needs.

const std = @import("std");

const galois = @import("galois.zig");

const Allocator = std.mem.Allocator;

/// How much error correction a code carries.
pub const Ecc = enum(u8) {
    low,
    medium,
    quartile,
    high,
};

/// The error correction level bits of the format information.
pub fn formatBits(ecc: Ecc) u8 {
    return switch (ecc) {
        .low => 0b01,
        .medium => 0b00,
        .quartile => 0b11,
        .high => 0b10,
    };
}

/// The error correction codewords per block, per level and version.
const ecc_codewords_per_block = [4][41]u8{
    // 0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40
    .{ 0, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28, 28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30 },
    .{ 0, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28 },
    .{ 0, 13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, 28, 26, 30, 28, 30, 30, 30, 30, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30 },
    .{ 0, 17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, 28, 26, 28, 30, 24, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30 },
};

/// The number of error correction blocks, per level and version.
const block_count = [4][41]u8{
    // 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40
    .{ 0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8, 8, 9, 9, 10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25 },
    .{ 0, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49 },
    .{ 0, 1, 1, 2, 2, 4, 4, 6, 6, 8, 8, 8, 10, 12, 16, 12, 17, 16, 18, 21, 20, 23, 23, 25, 27, 29, 34, 34, 35, 38, 40, 43, 45, 48, 51, 53, 56, 59, 62, 65, 68 },
    .{ 0, 1, 1, 2, 4, 4, 4, 5, 6, 8, 8, 11, 11, 16, 16, 18, 16, 19, 21, 25, 25, 25, 34, 30, 32, 35, 37, 40, 42, 45, 48, 51, 54, 57, 60, 63, 66, 70, 74, 77, 81 },
};

/// The number of data codewords a version and level can carry.
pub fn dataCodewordCount(version: u8, ecc: Ecc) usize {
    const level: usize = @backingInt(ecc);
    const raw = rawDataModules(version) / 8;
    const ecc_len: usize = ecc_codewords_per_block[level][version];
    const blocks: usize = block_count[level][version];
    return raw - ecc_len * blocks;
}

/// The number of modules of a version that carry data and error correction.
pub fn rawDataModules(version: u8) usize {
    var result: usize = (16 * @as(usize, version) + 128) * version + 64;
    if (version >= 2) {
        const alignment_count: usize = version / 7 + 2;
        result -= (25 * alignment_count - 10) * alignment_count - 55;
        if (version >= 7) result -= 36;
    }
    return result;
}

/// The number of bits the character count of byte mode takes.
pub fn characterCountBits(version: u8) u8 {
    return if (version <= 9) 8 else 16;
}

/// The number of bits the payload of `text_len` bytes takes. An empty text
/// has no segment at all, the same way the reference encoder does it.
pub fn segmentBits(text_len: usize, version: u8) usize {
    if (text_len == 0) return 0;
    return 4 + characterCountBits(version) + text_len * 8;
}

/// The smallest version that carries `text_len` bytes with the given error
/// correction level.
pub fn smallestVersion(text_len: usize, ecc: Ecc) ?u8 {
    var version: u8 = 1;
    while (version <= 40) : (version += 1) {
        const capacity_bits = dataCodewordCount(version, ecc) * 8;
        const needed_bits = segmentBits(text_len, version);
        if (needed_bits <= capacity_bits) return version;
    }
    return null;
}

/// A growing stream of bits, most significant bit first.
const BitBuffer = struct {
    bytes: []u8,
    bit_length: usize = 0,

    fn appendBits(self: *BitBuffer, value: u32, bit_count: u8) void {
        for (0..bit_count) |index| {
            const shift: u5 = @intCast(bit_count - 1 - index);
            const bit: u8 = @truncate((value >> shift) & 1);
            if (self.bit_length % 8 == 0) {
                self.bytes[self.bit_length / 8] = 0;
            }
            if (bit != 0) {
                self.bytes[self.bit_length / 8] |= @as(u8, 0x80) >> @as(u3, @intCast(self.bit_length % 8));
            }
            self.bit_length += 1;
        }
    }
};

/// Builds the data codewords of `text`: mode, length, payload, terminator and
/// the padding bytes.
pub fn dataCodewords(
    allocator: Allocator,
    version: u8,
    ecc: Ecc,
    text: []const u8,
) Allocator.Error![]u8 {
    const capacity = dataCodewordCount(version, ecc);
    var buffer = try allocator.alloc(u8, capacity);
    errdefer allocator.free(buffer);

    var bits = BitBuffer{ .bytes = buffer };
    // An empty text has no segment, the same way the reference encoder does it.
    if (text.len > 0) {
        bits.appendBits(0b0100, 4); // byte mode
        bits.appendBits(@intCast(text.len), characterCountBits(version));
        for (text) |byte| bits.appendBits(byte, 8);
    }

    // The terminator is at most four zero bits; the rest of the byte is
    // padded with zeros as well.
    const terminator: u8 = @intCast(@min(4, capacity * 8 - bits.bit_length));
    bits.appendBits(0, terminator);
    while (bits.bit_length % 8 != 0) bits.appendBits(0, 1);

    // The padding bytes alternate, as the standard prescribes.
    var pad_index: usize = bits.bit_length / 8;
    var pad_byte: u8 = 0xEC;
    while (pad_index < capacity) : ({
        pad_index += 1;
        pad_byte = if (pad_byte == 0xEC) 0x11 else 0xEC;
    }) {
        buffer[pad_index] = pad_byte;
    }
    return buffer;
}

/// Adds the error correction codewords and interleaves the blocks into the
/// final codeword sequence.
pub fn addEccAndInterleave(
    allocator: Allocator,
    version: u8,
    ecc: Ecc,
    data: []const u8,
) Allocator.Error![]u8 {
    const level: usize = @backingInt(ecc);
    const blocks = block_count[level][version];
    const ecc_len = ecc_codewords_per_block[level][version];
    const raw_codewords = rawDataModules(version) / 8;

    // The blocks that come first are the short ones.
    const short_block_len = raw_codewords / blocks;
    const short_block_count = blocks - raw_codewords % blocks;

    var generator: [galois.max_degree]u8 = undefined;
    galois.divisor(ecc_len, &generator);

    var block_data = try allocator.alloc([]u8, blocks);
    defer allocator.free(block_data);
    var block_ecc = try allocator.alloc([]u8, blocks);
    defer allocator.free(block_ecc);

    var offset: usize = 0;
    for (0..blocks) |index| {
        const data_len = short_block_len - ecc_len + @as(usize, if (index < short_block_count) 0 else 1);
        const payload = try allocator.dupe(u8, data[offset .. offset + data_len]);
        errdefer allocator.free(payload);
        offset += data_len;

        const rest = galois.remainder(payload, &generator, ecc_len);
        const correction = try allocator.dupe(u8, rest[0..ecc_len]);
        errdefer allocator.free(correction);

        block_data[index] = payload;
        block_ecc[index] = correction;
    }

    var result = std.ArrayList(u8).empty;
    errdefer result.deinit(allocator);

    // The data codewords of the blocks come first, then the error correction
    // codewords; within each part the blocks are interleaved.
    const max_data_len = short_block_len - ecc_len + 1;
    for (0..max_data_len) |index| {
        for (block_data) |payload| {
            if (index < payload.len) try result.append(allocator, payload[index]);
        }
    }
    for (0..ecc_len) |index| {
        for (block_ecc) |correction| {
            try result.append(allocator, correction[index]);
        }
    }

    for (block_data) |payload| allocator.free(payload);
    for (block_ecc) |correction| allocator.free(correction);

    return result.toOwnedSlice(allocator);
}

test "the smallest version fits the payload" {
    try std.testing.expectEqual(@as(u8, 1), smallestVersion(10, .medium).?);
    try std.testing.expectEqual(@as(u8, 1), smallestVersion(14, .medium).?);
    try std.testing.expectEqual(@as(u8, 2), smallestVersion(15, .medium).?);
}

test "a data segment is padded with the alternating bytes" {
    const codewords = try dataCodewords(std.testing.allocator, 1, .medium, "HELLO");
    defer std.testing.allocator.free(codewords);

    // Version 1 at level medium carries sixteen data codewords.
    try std.testing.expectEqual(@as(usize, 16), codewords.len);

    // Byte mode, the length, the payload, the terminator and the padding.
    try std.testing.expectEqual(@as(u8, 0x40), codewords[0]);
    try std.testing.expectEqual(@as(u8, 0x54), codewords[1]);
    try std.testing.expectEqual(@as(u8, 0xF0), codewords[6]);
    try std.testing.expectEqual(@as(u8, 0xEC), codewords[7]);
    try std.testing.expectEqual(@as(u8, 0x11), codewords[8]);
    try std.testing.expectEqual(@as(u8, 0xEC), codewords[15]);
}

test "the interleaved codewords keep the payload first" {
    const data = try dataCodewords(std.testing.allocator, 1, .medium, "HELLO");
    defer std.testing.allocator.free(data);

    const codewords = try addEccAndInterleave(std.testing.allocator, 1, .medium, data);
    defer std.testing.allocator.free(codewords);

    // The twenty-six codewords of the block start with the payload.
    try std.testing.expectEqual(@as(usize, 26), codewords.len);
    try std.testing.expectEqual(@as(u8, 0x40), codewords[0]);
}
