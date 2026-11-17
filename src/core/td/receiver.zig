//! The receiver thread loop: the only caller of the blocking `td_receive`.
//!
//! `td_receive` blocks and its returned string is valid only until the next
//! call in the same thread, so it must run in exactly one thread, which
//! copies every event before handing it to the queue.

const std = @import("std");

const td = @import("../td.zig");

/// Receiver thread body: blocks in `td_receive`, copies every event and hands
/// it to the queue. Strings returned by `td_receive` are only valid until the
/// next call in this thread, hence the copy.
pub fn receiverLoop(self: *td.Client) void {
    while (!self.stopping.load(.acquire)) {
        const raw = self.library.symbols.receive(self.receive_timeout_seconds) orelse
            continue;

        const copied = self.allocator.dupe(u8, std.mem.span(raw)) catch {
            // Out of memory: stop delivering events instead of spinning.
            std.log.warn("receiver thread stopped: out of memory", .{});
            break;
        };
        self.events.push(self.io, copied) catch {
            self.allocator.free(copied);
            break;
        };
    }
}
