//! The result of the encoder: the module matrix of a QR code.

const std = @import("std");

const Allocator = std.mem.Allocator;

/// An encoded QR code: the size of the matrix in modules and the modules
/// themselves, `true` for the dark ones.
pub const Code = struct {
    allocator: Allocator,
    version: u8,
    size: usize,
    modules: []bool,

    pub fn deinit(self: *Code) void {
        self.allocator.free(self.modules);
        self.* = undefined;
    }

    /// The module at the given column and row.
    pub fn module(self: *const Code, column: usize, row: usize) bool {
        return self.modules[row * self.size + column];
    }
};
