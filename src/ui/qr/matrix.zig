//! The module matrix of a QR code: the function patterns, the placement of
//! the data and the masks.

const std = @import("std");

const code = @import("code.zig");
const penalty = @import("penalty.zig");
const segments = @import("segments.zig");

const Allocator = std.mem.Allocator;

/// The module matrix while it is being built.
const Matrix = struct {
    version: u8,
    size: usize,
    /// True for the dark modules.
    modules: []bool,
    /// True for the modules that belong to a function pattern; the mask never
    /// touches them.
    is_function: []bool,

    /// Marks a module as a part of a function pattern.
    fn setFunction(self: *Matrix, x: usize, y: usize, dark: bool) void {
        self.modules[y * self.size + x] = dark;
        self.is_function[y * self.size + x] = true;
    }

    /// Draws the finder, alignment and timing patterns and reserves the areas
    /// of the format and version information.
    fn drawFunctionPatterns(self: *Matrix, ecc: segments.Ecc) void {
        // The timing patterns run over the whole code.
        for (0..self.size) |index| {
            self.setFunction(6, index, index % 2 == 0);
            self.setFunction(index, 6, index % 2 == 0);
        }

        // The three finder patterns, each with its separator.
        self.drawFinderPattern(3, 3);
        self.drawFinderPattern(self.size - 4, 3);
        self.drawFinderPattern(3, self.size - 4);

        // The alignment patterns; the ones that would overlap a finder
        // pattern are skipped.
        var positions: [7]u8 = undefined;
        const count = alignmentPositions(self.version, &positions);
        for (0..count) |x_index| {
            for (0..count) |y_index| {
                const overlaps_finder =
                    (x_index == 0 and y_index == 0) or
                    (x_index == 0 and y_index == count - 1) or
                    (x_index == count - 1 and y_index == 0);
                if (overlaps_finder) continue;
                self.drawAlignmentPattern(positions[x_index], positions[y_index]);
            }
        }

        // The format information is drawn with a placeholder mask first: this
        // reserves its area.
        self.drawFormatBits(ecc, 0);
        if (self.version >= 7) self.drawVersion();
    }

    /// Draws a finder pattern with its separator around the given center.
    fn drawFinderPattern(self: *Matrix, center_x: usize, center_y: usize) void {
        for (0..9) |index_y| {
            for (0..9) |index_x| {
                const offset_x = @as(isize, @intCast(index_x)) - 4;
                const offset_y = @as(isize, @intCast(index_y)) - 4;
                const x = @as(isize, @intCast(center_x)) + offset_x;
                const y = @as(isize, @intCast(center_y)) + offset_y;
                if (x < 0 or y < 0) continue;
                if (x >= self.size or y >= self.size) continue;

                const distance = @max(@abs(offset_x), @abs(offset_y));
                self.setFunction(
                    @intCast(x),
                    @intCast(y),
                    distance != 2 and distance != 4,
                );
            }
        }
    }

    /// Draws an alignment pattern with its center at the given position.
    fn drawAlignmentPattern(self: *Matrix, center_x: usize, center_y: usize) void {
        for (0..5) |index_y| {
            for (0..5) |index_x| {
                const offset_x = @as(isize, @intCast(index_x)) - 2;
                const offset_y = @as(isize, @intCast(index_y)) - 2;
                const distance = @max(@abs(offset_x), @abs(offset_y));
                self.setFunction(
                    @intCast(@as(isize, @intCast(center_x)) + offset_x),
                    @intCast(@as(isize, @intCast(center_y)) + offset_y),
                    distance != 1,
                );
            }
        }
    }

    /// Draws the format information of the level and the mask in both places
    /// the standard reserves for it.
    fn drawFormatBits(self: *Matrix, ecc: segments.Ecc, mask: u8) void {
        const data: u32 = @as(u32, segments.formatBits(ecc)) << 3 | mask;
        var remainder: u32 = data;
        for (0..10) |_| {
            remainder = (remainder << 1) ^ ((remainder >> 9) * 0x537);
        }
        const bits: u32 = (data << 10 | remainder) ^ 0x5412;

        for (0..6) |index| {
            self.setFunction(8, index, bitAt(bits, index));
        }
        self.setFunction(8, 7, bitAt(bits, 6));
        self.setFunction(8, 8, bitAt(bits, 7));
        self.setFunction(7, 8, bitAt(bits, 8));
        for (9..15) |index| {
            self.setFunction(14 - index, 8, bitAt(bits, index));
        }

        for (0..8) |index| {
            self.setFunction(self.size - 1 - index, 8, bitAt(bits, index));
        }
        for (8..15) |index| {
            self.setFunction(8, self.size - 15 + index, bitAt(bits, index));
        }
        // The module above the lower left finder pattern is always dark.
        self.setFunction(8, self.size - 8, true);
    }

    /// Draws the version information; it exists only from version 7 on.
    fn drawVersion(self: *Matrix) void {
        const version: u32 = self.version;
        var remainder: u32 = version;
        for (0..12) |_| {
            remainder = (remainder << 1) ^ ((remainder >> 11) * 0x1F25);
        }
        const bits: u32 = version << 12 | remainder;

        for (0..18) |index| {
            const dark = bitAt(bits, index);
            const a = self.size - 11 + index % 3;
            const b = index / 3;
            self.setFunction(a, b, dark);
            self.setFunction(b, a, dark);
        }
    }

    /// Places the codewords in the zigzag pattern of the standard.
    fn drawCodewords(self: *Matrix, codewords: []const u8) void {
        var bit_index: usize = 0;

        var right: isize = @intCast(self.size - 1);
        while (right >= 1) : (right -= 2) {
            // The column of the timing pattern is skipped.
            if (right == 6) right = 5;

            for (0..self.size) |vertical| {
                for (0..2) |column| {
                    const x = right - @as(isize, @intCast(column));
                    const upward = ((right + 1) & 2) == 0;
                    const y = if (upward) self.size - 1 - vertical else vertical;

                    if (self.is_function[y * self.size + @as(usize, @intCast(x))]) continue;
                    if (bit_index >= codewords.len * 8) continue;

                    const byte = codewords[bit_index / 8];
                    self.modules[y * self.size + @as(usize, @intCast(x))] =
                        bitAt(byte, 7 - @as(u3, @intCast(bit_index % 8)));
                    bit_index += 1;
                }
            }
        }
    }

    /// Applies the given mask to the data modules.
    fn applyMask(self: *Matrix, mask: u8) void {
        for (0..self.size) |y| {
            for (0..self.size) |x| {
                if (self.is_function[y * self.size + x]) continue;
                if (maskAt(mask, x, y)) {
                    self.modules[y * self.size + x] = !self.modules[y * self.size + x];
                }
            }
        }
    }

    /// Applies every mask and keeps the one with the lowest penalty score.
    fn chooseMask(self: *Matrix, ecc: segments.Ecc) void {
        var best_mask: u8 = 0;
        var best_score: usize = std.math.maxInt(usize);

        for (0..8) |mask| {
            self.applyMask(@intCast(mask));
            self.drawFormatBits(ecc, @intCast(mask));

            const current = penalty.score(self.modules, self.size);
            if (current < best_score) {
                best_score = current;
                best_mask = @intCast(mask);
            }

            // The mask is removed again: the format bits of the next mask
            // overwrite the ones of this one anyway.
            self.applyMask(@intCast(mask));
        }

        self.applyMask(best_mask);
        self.drawFormatBits(ecc, best_mask);
    }
};

/// Builds the matrix of a QR code from its codewords and returns the code
/// with the best mask applied.
pub fn build(
    allocator: Allocator,
    version: u8,
    ecc: segments.Ecc,
    codewords: []const u8,
) Allocator.Error!code.Code {
    const size: usize = 17 + 4 * @as(usize, version);

    const modules = try allocator.alloc(bool, size * size);
    errdefer allocator.free(modules);
    const is_function = try allocator.alloc(bool, size * size);
    defer allocator.free(is_function);

    var matrix = Matrix{
        .version = version,
        .size = size,
        .modules = modules,
        .is_function = is_function,
    };
    @memset(matrix.modules, false);
    @memset(matrix.is_function, false);

    matrix.drawFunctionPatterns(ecc);
    matrix.drawCodewords(codewords);
    matrix.chooseMask(ecc);

    return code.Code{
        .allocator = allocator,
        .version = version,
        .size = size,
        .modules = modules,
    };
}

/// The centers of the alignment patterns of a version; the count of them is
/// returned.
fn alignmentPositions(version: u8, out: *[7]u8) usize {
    if (version == 1) return 0;

    const count: usize = version / 7 + 2;
    const step: usize = if (version == 32)
        26
    else
        (version * 4 + count * 2 + 1) / (count * 2 - 2) * 2;

    var index: usize = count - 1;
    var position: usize = version * 4 + 10;
    while (index > 0) : (index -= 1) {
        out[index] = @intCast(position);
        // The final decrement would run past zero; the reference discards it.
        if (index > 1) position -= step;
    }
    out[0] = 6;
    return count;
}

/// Reads the bit with the given index of a value; the bits are counted from
/// the least significant one.
fn bitAt(value: u32, index: usize) bool {
    return (value >> @as(u5, @intCast(index))) & 1 != 0;
}

/// Tells whether the mask flips the module at the given position.
fn maskAt(mask: u8, x: usize, y: usize) bool {
    const column: u32 = @intCast(x);
    const row: u32 = @intCast(y);

    return switch (mask) {
        0 => (column + row) % 2 == 0,
        1 => row % 2 == 0,
        2 => column % 3 == 0,
        3 => (column + row) % 3 == 0,
        4 => (column / 3 + row / 2) % 2 == 0,
        5 => column * row % 2 + column * row % 3 == 0,
        6 => (column * row % 2 + column * row % 3) % 2 == 0,
        else => ((column + row) % 2 + column * row % 3) % 2 == 0,
    };
}
