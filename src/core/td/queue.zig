//! The thread-safe event queue between the receiver thread and the consumer.

const std = @import("std");

const Io = std.Io;

const assert = std.debug.assert;

/// Converts milliseconds into an `Io.Timeout`.
pub fn timeoutMs(ms: u32) Io.Timeout {
    return .{ .duration = .{
        .raw = Io.Duration.fromMilliseconds(@intCast(ms)),
        .clock = .awake,
    } };
}

/// A bounded ring buffer of owned event strings.
pub const EventQueue = struct {
    pub const PushError = error{ QueueClosed, Canceled };
    pub const PopError = error{Canceled};

    allocator: std.mem.Allocator,
    capacity: usize,
    buffer: [][]u8,
    head: usize,
    count: usize,
    mutex: Io.Mutex = .init,
    not_empty: Io.Condition = .init,
    not_full: Io.Condition = .init,
    closed: bool = false,

    pub fn init(
        allocator: std.mem.Allocator,
        capacity: usize,
    ) std.mem.Allocator.Error!EventQueue {
        assert(capacity > 0);
        const buffer = try allocator.alloc([]u8, capacity);
        return .{
            .allocator = allocator,
            .capacity = capacity,
            .buffer = buffer,
            .head = 0,
            .count = 0,
        };
    }

    /// Frees buffered events and the ring itself. Call after the receiver
    /// thread has stopped.
    pub fn deinit(self: *EventQueue, io: Io) void {
        self.mutex.lockUncancelable(io);
        // Unlock before `self.* = undefined`, so no deferred unlock can run
        // on a corrupted mutex.
        var index = self.head;
        var remaining = self.count;
        while (remaining > 0) : (remaining -= 1) {
            self.allocator.free(self.buffer[index]);
            index = (index + 1) % self.capacity;
        }
        self.allocator.free(self.buffer);
        self.mutex.unlock(io);
        self.* = undefined;
    }

    /// Takes ownership of `bytes` on success; on error the caller still owns
    /// it.
    pub fn push(self: *EventQueue, io: Io, bytes: []u8) PushError!void {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);

        while (self.count == self.capacity and !self.closed) {
            self.not_full.waitUncancelable(io, &self.mutex);
        }
        if (self.closed) return error.QueueClosed;

        const tail = (self.head + self.count) % self.capacity;
        self.buffer[tail] = bytes;
        self.count += 1;
        self.not_empty.signal(io);
    }

    /// Returns an owned event string, or null when empty (or closed and
    /// drained) after the timeout.
    pub fn pop(self: *EventQueue, io: Io, timeout: Io.Timeout) PopError!?[]u8 {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);

        while (self.count == 0) {
            if (self.closed) return null;
            self.not_empty.waitTimeout(io, &self.mutex, timeout) catch |err|
                switch (err) {
                    error.Timeout => return null,
                    error.Canceled => continue,
                };
        }

        const bytes = self.buffer[self.head];
        self.head = (self.head + 1) % self.capacity;
        self.count -= 1;
        self.not_full.signal(io);
        return bytes;
    }

    /// Marks the queue closed; unblocks waiting pushers and consumers.
    pub fn close(self: *EventQueue, io: Io) void {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);

        self.closed = true;
        self.not_full.broadcast(io);
        self.not_empty.broadcast(io);
    }
};

test "event queue preserves order and closes cleanly" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var queue = try EventQueue.init(allocator, 4);
    defer queue.deinit(io);

    try queue.push(io, try allocator.dupe(u8, "first"));
    try queue.push(io, try allocator.dupe(u8, "second"));

    const first = (try queue.pop(io, timeoutMs(0))) orelse
        return error.TestUnexpectedResult;
    defer allocator.free(first);
    try std.testing.expectEqualStrings("first", first);

    const second = (try queue.pop(io, timeoutMs(0))) orelse
        return error.TestUnexpectedResult;
    defer allocator.free(second);
    try std.testing.expectEqualStrings("second", second);

    // Empty queue: a zero timeout returns null instead of blocking.
    try std.testing.expectEqual(
        @as(?[]u8, null),
        try queue.pop(io, timeoutMs(0)),
    );

    queue.close(io);
    try std.testing.expectEqual(
        @as(?[]u8, null),
        try queue.pop(io, timeoutMs(0)),
    );
}

test "event queue rejects pushes after close" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var queue = try EventQueue.init(allocator, 2);
    defer queue.deinit(io);

    queue.close(io);
    const late = try allocator.dupe(u8, "late");
    defer allocator.free(late);
    try std.testing.expectError(error.QueueClosed, queue.push(io, late));
}
