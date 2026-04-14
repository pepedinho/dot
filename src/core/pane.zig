const gap = @import("gap.zig");

/// A `View` represent a rectangular viewport on the terminal screen.
/// It act as a 'camera' looking into a specific `GapBuffer`.
///
/// While the `GapBuffer` strictly holds the raw text data, the `View` manages
/// the visual representation: screen coordinate (x, y), dimension (width, height),
/// scroll offset, and UI states (read-only, dirty, flags).
///
/// Multiple views can exist simulataneously (e.g., via split panes),
/// pointing to different buffers or even different parts of the same buffer.
pub const View = struct {
    /// Absolute terminal column position.
    x: u16,
    /// Absolute terminal row position.
    y: u16,
    /// Visible width of the viewport in columns.
    width: u16,
    /// Visible height of the viewport in rows.
    height: u16,

    ///The vertical scroll position (number of logical lines hidden above).
    row_offset: usize = 0,
    /// The horizontal scroll position (number of logical columns hidden to the left).
    col_offset: usize = 0,
    /// Pointer to the underlying text data.
    buf: *gap.GapBuffer,
    /// If true, blocks any Insert or Delete actions from the user.
    is_readonly: bool = false,
    /// If true, the UI engine will redraw this specific viewport on the next tick.
    is_dirty: bool = false,
    /// for lines numbers
    gutter_width: u16 = 4,

    pub fn scroll(self: *View) bool {
        var camera_moved = false;
        const pos = self.buf.getCursorPos();

        if (pos.y <= self.row_offset) {
            self.row_offset = pos.y - 1;
            camera_moved = true;
        }

        if (pos.y >= self.row_offset + self.height) {
            self.row_offset = pos.y - self.height + 1;
            camera_moved = true;
        }

        if (pos.x <= self.col_offset) {
            self.col_offset = pos.x - 1;
            camera_moved = true;
        }
        if (pos.x >= self.col_offset + self.width) {
            self.col_offset = pos.x - self.width + 1;
            camera_moved = true;
        }

        return camera_moved;
    }
};
