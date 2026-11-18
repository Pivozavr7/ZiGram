//! Arithmetic of the Galois field GF(256) that the Reed-Solomon error
//! correction of QR codes is built on.
//!
//! The field uses the primitive polynomial x^8 + x^4 + x^3 + x^2 + 1
//! (0x11D), the one the QR code standard prescribes.

const std = @import("std");

/// The largest number of error correction codewords of a block; the tables
/// of the standard never ask for more.
pub const max_degree = 30;

/// The exponents of the field: `exp_table[i]` is 2^i.
const exp_table = buildExpTable();

/// The logarithms of the field: `log_table[x]` is the exponent of x.
const log_table = buildLogTable();

fn buildExpTable() [255]u8 {
    // The period of the field is 255, so every exponent fits into the table.
    var table: [255]u8 = undefined;
    var value: u16 = 1;
    for (&table) |*entry| {
        entry.* = @intCast(value);
        value <<= 1;
        if (value & 0x100 != 0) value ^= 0x11D;
    }
    return table;
}

fn buildLogTable() [256]u8 {
    var table: [256]u8 = @splat(0);
    var value: u16 = 1;
    for (0..255) |exponent| {
        table[@intCast(value)] = @intCast(exponent);
        value <<= 1;
        if (value & 0x100 != 0) value ^= 0x11D;
    }
    return table;
}

/// Multiplies two field elements.
pub fn multiply(x: u8, y: u8) u8 {
    if (x == 0) return 0;
    if (y == 0) return 0;

    const sum: usize = @as(usize, log_table[x]) + log_table[y];
    return exp_table[sum % 255];
}

/// The Reed-Solomon generator polynomial of the given degree.
/// The coefficients are in descending order and the leading one, which is
/// always 1, is not stored.
pub fn divisor(degree: u8, out: *[max_degree]u8) void {
    std.debug.assert(degree >= 1 and degree <= max_degree);
    @memset(out, 0);

    // The monomial x^0: the constant term of the product polynomial.
    out[degree - 1] = 1;

    // The product of the factors (x - r^i), with r = 2.
    var root: u8 = 1;
    for (0..degree) |_| {
        for (0..degree) |index| {
            out[index] = multiply(out[index], root);
            if (index + 1 < degree) out[index] ^= out[index + 1];
        }
        root = multiply(root, 0x02);
    }
}

/// The Reed-Solomon remainder of `data` divided by `polynomial`: the error
/// correction codewords of the block.
pub fn remainder(
    data: []const u8,
    polynomial: *const [max_degree]u8,
    degree: u8,
) [max_degree]u8 {
    std.debug.assert(degree >= 1 and degree <= max_degree);

    var result: [max_degree]u8 = @splat(0);
    for (data) |byte| {
        const factor = byte ^ result[0];

        // The register shifts by one codeword.
        for (0..degree - 1) |index| result[index] = result[index + 1];
        result[degree - 1] = 0;

        for (0..degree) |index| {
            result[index] ^= multiply(polynomial[index], factor);
        }
    }
    return result;
}

test "the field multiplication matches the known values" {
    try std.testing.expectEqual(@as(u8, 0), multiply(0, 123));
    try std.testing.expectEqual(@as(u8, 0), multiply(123, 0));
    try std.testing.expectEqual(@as(u8, 123), multiply(1, 123));
    // 0x53 * 0xCA = 0x8F in the QR field, checked by polynomial multiplication.
    try std.testing.expectEqual(@as(u8, 0x8F), multiply(0x53, 0xCA));
    // The field has 255 elements, so the powers of two cycle.
    try std.testing.expectEqual(@as(u8, 2), multiply(2, 1));
}

test "the generator polynomial of degree ten is known" {
    var generator: [max_degree]u8 = undefined;
    divisor(10, &generator);

    // The polynomial of the standard, as the reference encoder computes it.
    const expected = [_]u8{ 0xD8, 0xC2, 0x9F, 0x6F, 0xC7, 0x5E, 0x5F, 0x71, 0x9D, 0xC1 };
    try std.testing.expectEqualSlices(u8, &expected, generator[0..10]);
}

test "appending the remainder makes the message divisible" {
    var generator: [max_degree]u8 = undefined;
    divisor(10, &generator);

    const data = "HELLO WORLD";
    const rest = remainder(data, &generator, 10);

    var codeword: [data.len + 10]u8 = undefined;
    @memcpy(codeword[0..data.len], data);
    @memcpy(codeword[data.len..], rest[0..10]);

    const check = remainder(&codeword, &generator, 10);
    for (check[0..10]) |byte| {
        try std.testing.expectEqual(@as(u8, 0), byte);
    }
}
