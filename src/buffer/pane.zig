const gap = @import("gap.zig");

pub const View = struct {
    x: u16,
    y: u16,
    width: u16,
    height: u16,
    row_offset: usize = 0,
    col_offset: usize = 0,
    buf: *gap.GapBuffer,

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
