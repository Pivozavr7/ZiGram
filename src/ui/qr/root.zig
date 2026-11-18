//! The public API of the QR encoder: text in, module matrix out.
//!
//! Only byte mode is supported, which carries any UTF-8 text and is what the
//! Telegram login link needs. The encoder is a port of the QR Code generator
//! by Nayuki and produces the same matrices.

const std = @import("std");

const code = @import("code.zig");
const matrix = @import("matrix.zig");
const segments = @import("segments.zig");

const Allocator = std.mem.Allocator;

/// How much error correction a code carries.
pub const Ecc = segments.Ecc;

/// An encoded QR code: the module matrix with its size.
pub const Code = code.Code;

pub const Error = error{PayloadTooLarge} || Allocator.Error;

/// Encodes `text` into a QR code with the given error correction level and
/// the smallest version that fits the payload. The caller owns the code and
/// must call `deinit` on it.
pub fn encode(allocator: Allocator, text: []const u8, ecc: Ecc) Error!Code {
    const version = segments.smallestVersion(text.len, ecc) orelse
        return error.PayloadTooLarge;

    const data = try segments.dataCodewords(allocator, version, ecc, text);
    defer allocator.free(data);

    const codewords = try segments.addEccAndInterleave(allocator, version, ecc, data);
    defer allocator.free(codewords);

    return matrix.build(allocator, version, ecc, codewords);
}

test {
    _ = @import("code.zig");
    _ = @import("galois.zig");
    _ = @import("matrix.zig");
    _ = @import("penalty.zig");
    _ = @import("segments.zig");
    _ = @import("root_test.zig");
}
