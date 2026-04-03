const std = @import("std");
const utils = @import("../utils.zig");

const TAB_SIZE: usize = 8;

/// Gap buffer implementation
pub const GapBuffer = struct {
    allocator: std.mem.Allocator,
    buffer: []u8,
    /// The physical index representing the start of the gap.
    /// This also corresponds to the logical position of the cursor.
    /// All characters from `buffer[0..gap_start]` are the text BEFORE the cursor
    gap_start: usize,
    /// The physical index representing the end of the gap.
    /// All characters from `buffer[gap_end..buffer.len]` are the text AFTER the cursor.
    gap_end: usize,

    const INITIAL_CAPACITY = 1024;

    /// Initializes an empty Gap Buffer with an initial capacity.
    /// The gap spans the entire buffer initially.
    pub fn init(allocator: std.mem.Allocator) !GapBuffer {
        const buf = try allocator.alloc(u8, INITIAL_CAPACITY);
        @memset(buf, 0);
        return GapBuffer{
            .allocator = allocator,
            .buffer = buf,
            .gap_start = 0,
            .gap_end = buf.len,
        };
    }

    /// Initializes a Gap Buffer loaded with predefined text.
    /// The gap is placed exactly after the provided text, ready for appending.
    pub fn initFromFile(allocator: std.mem.Allocator, text: []const u8) !GapBuffer {
        const total_capacity = text.len + INITIAL_CAPACITY;
        const buf = try allocator.alloc(u8, total_capacity);

        @memcpy(buf[0..text.len], text);
        @memset(buf[text.len..total_capacity], 0);

        return GapBuffer{
            .allocator = allocator,
            .buffer = buf,
            .gap_start = text.len,
            .gap_end = total_capacity,
        };
    }

    /// Doubles the physical capacity of the buffer when the gap is exhausted.
    /// This requires allocating a new block, copying the left part, and moving the right part to the end.
    fn expand(self: *GapBuffer) !void {
        const new_capacity = self.buffer.len * 2;
        const buf = try self.allocator.alloc(u8, new_capacity);
        @memmove(buf[0..self.gap_start], self.buffer[0..self.gap_start]);

        const right_part_len = self.buffer.len - self.gap_end;
        const new_gap_end = new_capacity - right_part_len;

        @memcpy(buf[new_gap_end..new_capacity], self.buffer[self.gap_end..self.buffer.len]);

        self.allocator.free(self.buffer);
        self.buffer = buf;
        self.gap_end = new_gap_end;
    }

    pub fn deinit(self: *GapBuffer) void {
        self.allocator.free(self.buffer);
    }

    /// Moves the cursor (and the gap) one character to the left.
    /// This physically takes the character just before the gap and copies it to the end of the gap.
    pub fn moveCursorLeft(self: *GapBuffer) void {
        if (self.gap_start > 0) {
            self.gap_start -= 1;
            self.gap_end -= 1;
            self.buffer[self.gap_end] = self.buffer[self.gap_start];
        }
    }

    /// Moves the cursor (and the gap) one character to the right.
    /// This physically takes the character just after the gap and copies it to the start of the gap.
    pub fn moveCursorRight(self: *GapBuffer) void {
        if (self.gap_end < self.buffer.len) {
            self.buffer[self.gap_start] = self.buffer[self.gap_end];
            self.gap_start += 1;
            self.gap_end += 1;
        }
    }

    pub fn moveCursorUp(self: *GapBuffer) void {
        const pos = self.getCursorPos();
        if (pos.y == 1) return;

        while (self.gap_start > 0 and self.buffer[self.gap_start - 1] != '\n') {
            self.moveCursorLeft();
        }

        self.moveCursorLeft();

        while (self.gap_start > 0 and self.buffer[self.gap_start - 1] != '\n') {
            self.moveCursorLeft();
        }

        var target_x = pos.x;
        while (target_x > 1 and self.gap_end < self.buffer.len and self.buffer[self.gap_end] != '\n') {
            self.moveCursorRight();
            target_x -= 1;
        }
    }

    pub fn moveCursorDown(self: *GapBuffer) void {
        const pos = self.getCursorPos();

        while (self.gap_end < self.buffer.len and self.buffer[self.gap_end] != '\n') {
            self.moveCursorRight();
        }

        if (self.gap_end == self.buffer.len) return;

        self.moveCursorRight();
        var target_x = pos.x;
        while (target_x > 1 and self.gap_end < self.buffer.len and self.buffer[self.gap_end] != '\n') {
            self.moveCursorRight();
            target_x -= 1;
        }
    }

    /// Inserts a character exactly at the cursor's logical position in O(1) time.
    /// Consumes one byte of the gap. Expands the buffer if the gap is empty.
    pub fn insertChar(self: *GapBuffer, char: u8) !void {
        if (self.gap_start == self.gap_end) {
            try self.expand();
        }

        self.buffer[self.gap_start] = char;
        self.gap_start += 1;
    }

    /// Removes the character immediately preceding the cursor in O(1) time.
    /// This simply expands the gap backwards by one byte.
    pub fn backspace(self: *GapBuffer) void {
        if (self.gap_start > 0) {
            self.gap_start -= 1;
        }
    }

    pub fn printDebug(self: *GapBuffer) void {
        std.debug.print("Texte: '{s}{s}' | start: {d}, end: {d}\n", .{
            self.buffer[0..self.gap_start],
            self.buffer[self.gap_end..self.buffer.len],
            self.gap_start,
            self.gap_end,
        });
    }

    /// Returns a slice pointing to the text physically located BEFORE the cursor.
    pub fn getFirst(self: *GapBuffer) []u8 {
        return self.buffer[0..self.gap_start];
    }

    /// Returns a slice pointing to the text physically located AFTER the cursor.
    pub fn getSecond(self: *GapBuffer) []u8 {
        return self.buffer[self.gap_end..self.buffer.len];
    }

    /// Calculates the 2D logical position (x, y) of the cursor by iterating
    /// through the left part of the buffer and counting newlines and tabs.
    pub fn getCursorPos(self: *GapBuffer) struct { x: usize, y: usize } {
        var x: usize = 1;
        var y: usize = 1;

        for (self.buffer[0..self.gap_start]) |c| {
            if (c == '\n') {
                y += 1;
                x = 1;
            } else if (c == '\t') {
                x += TAB_SIZE;
            } else {
                x += 1;
            }
        }

        return .{ .y = y, .x = x };
    }

    /// Moves the gap to an arbitrary (x, y) logical coordinate.
    /// This translates the logical 2D coordinate into a physical array index,
    /// and shifts the gap by copying blocks of memory.
    pub fn jumpTo(self: *GapBuffer, pos: utils.Pos) void {
        const gap_size = self.gap_end - self.gap_start;
        const logical_len = self.buffer.len - gap_size;

        var target_logical_idx: usize = 0;
        var current_y: usize = 1;
        var current_x: usize = 1;

        while (target_logical_idx < logical_len) {
            if (current_y == pos.y and current_x >= pos.x) break;

            const physical_idx = if (target_logical_idx < self.gap_start)
                target_logical_idx
            else
                target_logical_idx + gap_size;

            const c = self.buffer[physical_idx];
            if (current_y == pos.y and c == '\n') break;

            if (c == '\n') {
                current_y += 1;
                current_x = 1;
                if (current_y > pos.y) break;
            } else if (c == '\t') {
                current_x += TAB_SIZE;
            } else {
                current_x += 1;
            }

            target_logical_idx += 1;
        }

        if (target_logical_idx < self.gap_start) {
            const shift_len = self.gap_start - target_logical_idx;
            const dest = self.gap_end - shift_len;

            std.mem.copyBackwards(u8, self.buffer[dest .. dest + shift_len], self.buffer[target_logical_idx..self.gap_start]);
            self.gap_start -= shift_len;
            self.gap_end -= shift_len;
        } else if (target_logical_idx > self.gap_start) {
            const shift_len = target_logical_idx - self.gap_start;
            std.mem.copyForwards(u8, self.buffer[self.gap_start .. self.gap_start + shift_len], self.buffer[self.gap_end .. self.gap_end + shift_len]);
            self.gap_start += shift_len;
            self.gap_end += shift_len;
        }
    }
};
