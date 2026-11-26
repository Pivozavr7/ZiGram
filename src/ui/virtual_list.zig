//! The visible range of a virtualized list of measured item heights.
//!
//! The list knows the height of every item, so the screen can skip the
//! ones outside the viewport and pad the rest with spacers of the same
//! height. This is pure arithmetic: the renderer only draws what it says.

const std = @import("std");

/// The slice of a list that fits the viewport, plus the spacers around it.
pub const Range = struct {
    /// First item to draw.
    start: usize,
    /// One past the last item to draw; equal to `start` for an empty view.
    end: usize,
    /// Total height of the items above the first drawn one.
    top: f32,
    /// Total height of the items below the last drawn one.
    bottom: f32,
};

/// Splits the heights into what a viewport at `scroll_y` can see. Items
/// that touch neither edge are left out; their height is reported in
/// `top` and `bottom` so the renderer can replace them with spacers.
pub fn visibleRange(heights: []const f32, scroll_y: f32, view_height: f32) Range {
    var range: Range = .{ .start = 0, .end = 0, .top = 0, .bottom = 0 };
    const bottom_edge = scroll_y + view_height;

    while (range.start < heights.len and range.top + heights[range.start] <= scroll_y) {
        range.top += heights[range.start];
        range.start += 1;
    }

    range.end = range.start;
    var drawn = range.top;
    while (range.end < heights.len and drawn < bottom_edge) {
        drawn += heights[range.end];
        range.end += 1;
    }

    range.bottom = totalHeight(heights) - drawn;
    return range;
}

/// The summed height of every item.
pub fn totalHeight(heights: []const f32) f32 {
    var total: f32 = 0;
    for (heights) |height| total += height;
    return total;
}

test "the first viewport draws from the top" {
    const heights = [_]f32{ 50, 50, 50, 50 };
    const range = visibleRange(&heights, 0, 120);

    try std.testing.expectEqual(@as(usize, 0), range.start);
    try std.testing.expectEqual(@as(usize, 3), range.end);
    try std.testing.expectEqual(@as(f32, 0), range.top);
    try std.testing.expectEqual(@as(f32, 50), range.bottom);
}

test "scrolled away items become a top spacer" {
    const heights = [_]f32{ 50, 50, 50, 50 };
    const range = visibleRange(&heights, 60, 60);

    try std.testing.expectEqual(@as(usize, 1), range.start);
    try std.testing.expectEqual(@as(usize, 3), range.end);
    try std.testing.expectEqual(@as(f32, 50), range.top);
    try std.testing.expectEqual(@as(f32, 50), range.bottom);
}

test "the end of the list is reached" {
    const heights = [_]f32{ 50, 50 };
    const range = visibleRange(&heights, 150, 100);

    try std.testing.expectEqual(@as(usize, 2), range.start);
    try std.testing.expectEqual(@as(usize, 2), range.end);
    try std.testing.expectEqual(@as(f32, 100), range.top);
    try std.testing.expectEqual(@as(f32, 0), range.bottom);
}

test "an empty list has an empty range" {
    const range = visibleRange(&[_]f32{}, 0, 600);

    try std.testing.expectEqual(@as(usize, 0), range.start);
    try std.testing.expectEqual(@as(usize, 0), range.end);
    try std.testing.expectEqual(@as(f32, 0), range.top);
    try std.testing.expectEqual(@as(f32, 0), range.bottom);
}

test "the spacers and the drawn slice sum to the total height" {
    const heights = [_]f32{ 30, 45, 60, 75, 90 };
    const range = visibleRange(&heights, 40, 100);

    var sum = range.top + range.bottom;
    for (heights[range.start..range.end]) |height| sum += height;
    try std.testing.expectEqual(totalHeight(&heights), sum);
}
