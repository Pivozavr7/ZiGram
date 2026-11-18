//! The penalty score of a QR code.
//!
//! The score tells how hard a code is to scan: long runs of the same color,
//! finder-like patterns and an unbalanced amount of dark and light modules
//! all make a code worse. The mask with the lowest score is the best one.

const std = @import("std");

/// The weight of a run of five or more modules of the same color.
const penalty_run = 3;
/// The weight of a block of two by two modules of the same color.
const penalty_block = 3;
/// The weight of a finder-like pattern.
const penalty_finder = 40;
/// The weight of an unbalanced amount of dark and light modules.
const penalty_balance = 10;

/// The score of the given module matrix; the lower, the better.
pub fn score(modules: []const bool, size: usize) usize {
    var result: usize = 0;
    result += scoreLines(modules, size, true);
    result += scoreLines(modules, size, false);
    result += scoreBlocks(modules, size);
    result += scoreBalance(modules, size);
    return result;
}

/// The score of all rows or all columns.
fn scoreLines(modules: []const bool, size: usize, by_row: bool) usize {
    var result: usize = 0;

    for (0..size) |line| {
        var run_color = false;
        var run_length: usize = 0;
        var history: [7]usize = @splat(0);

        for (0..size) |index| {
            const dark = moduleAt(modules, size, line, index, by_row);
            if (dark == run_color) {
                run_length += 1;
                if (run_length == 5) {
                    result += penalty_run;
                } else if (run_length > 5) {
                    result += 1;
                }
            } else {
                addHistory(&history, run_length, size);
                if (!run_color) result += countPatterns(&history) * penalty_finder;
                run_color = dark;
                run_length = 1;
            }
        }
        result += terminateAndCount(run_color, run_length, &history, size) * penalty_finder;
    }
    return result;
}

/// The score of the blocks of two by two modules of the same color.
fn scoreBlocks(modules: []const bool, size: usize) usize {
    var result: usize = 0;

    for (0..size - 1) |row| {
        for (0..size - 1) |column| {
            const dark = moduleAt(modules, size, row, column, true);
            if (dark == moduleAt(modules, size, row, column + 1, true) and
                dark == moduleAt(modules, size, row + 1, column, true) and
                dark == moduleAt(modules, size, row + 1, column + 1, true))
            {
                result += penalty_block;
            }
        }
    }
    return result;
}

/// The score of the balance between the dark and the light modules.
fn scoreBalance(modules: []const bool, size: usize) usize {
    var dark: usize = 0;
    for (modules) |module| {
        if (module) dark += 1;
    }

    const total = size * size;
    const difference = if (dark * 20 > total * 10)
        dark * 20 - total * 10
    else
        total * 10 - dark * 20;
    const steps = (difference + total - 1) / total - 1;
    return steps * penalty_balance;
}

/// Reads a module of a row or of a column.
fn moduleAt(
    modules: []const bool,
    size: usize,
    line: usize,
    index: usize,
    by_row: bool,
) bool {
    const row = if (by_row) line else index;
    const column = if (by_row) index else line;
    return modules[row * size + column];
}

/// Adds a run of modules to the history of the finder-like patterns.
fn addHistory(history: *[7]usize, run_length: usize, size: usize) void {
    var length = run_length;
    // The light border around the code counts as a part of the first run.
    if (history[0] == 0) length += size;

    // The runs shift back: the newest one takes the first slot.
    var index: usize = history.len - 1;
    while (index > 0) : (index -= 1) {
        history[index] = history[index - 1];
    }
    history[0] = length;
}

/// Counts the finder-like patterns in the run history.
fn countPatterns(history: *const [7]usize) usize {
    const unit = history[1];
    const core = unit > 0 and
        history[2] == unit and
        history[3] == unit * 3 and
        history[4] == unit and
        history[5] == unit;

    var result: usize = 0;
    if (core and history[0] >= unit * 4 and history[6] >= unit) result += 1;
    if (core and history[6] >= unit * 4 and history[0] >= unit) result += 1;
    return result;
}

/// Closes the last run of a line and counts its finder-like patterns.
fn terminateAndCount(
    run_color: bool,
    run_length: usize,
    history: *[7]usize,
    size: usize,
) usize {
    var length = run_length;
    if (run_color) {
        addHistory(history, length, size);
        length = 0;
    }
    // The light border around the code counts as a part of the last run.
    length += size;
    addHistory(history, length, size);
    return countPatterns(history);
}

test "a uniform matrix has a high score" {
    var modules: [21 * 21]bool = @splat(false);
    const uniform = score(&modules, 21);

    // A checkerboard has no runs of the same color.
    for (0..21) |row| {
        for (0..21) |column| {
            modules[row * 21 + column] = (row + column) % 2 == 0;
        }
    }
    const checkerboard = score(&modules, 21);

    try std.testing.expect(uniform > checkerboard);
}
