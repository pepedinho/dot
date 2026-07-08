//! This module defines the visual appearance primitives for Zui.
//!
//! It provides the foundational building blocks (`Color`, `Modifier`, and `Style`)
//! to declaratively describe how text and widgets should look, without tying
//! them to specific terminal ANSI escape sequences.
//!
//! Styles in Zui are designed to be composable. By using optional values
//! for colors and bitsets for modifiers, styles can be patched and merged together
//! to cascade visual properties (similar to CSS inheritance).

const std = @import("std");

pub const Color = union(enum) {
    Reset,
    Black,
    Red,
    Green,
    Yellow,
    Blue,
    Magenta,
    Cyan,
    White,
    /// 24-bit RGB true color.
    RGB: struct { r: u8, g: u8, b: u8 },
    /// 8-bit ANSI color index (0-255)
    ANSI: u8,
};

pub const Modifier = packed struct {
    bold: bool = false,
    dim: bool = false,
    italic: bool = false,
    underlined: bool = false,
    slow_blink: bool = false,
    rapid_blink: bool = false,
    reversed: bool = false,
    hidden: bool = false,
    crossed_out: bool = false,
    _padding: u7 = 0,
};

pub const Style = struct {
    const Self = @This();

    fg: ?Color = null,
    bg: ?Color = null,
    add_modifier: Modifier = .{},
    sub_modifier: Modifier = .{},

    pub fn init() Self {
        return .{};
    }

    /// Set the forground color
    pub fn wfg(self: Self, color: Color) Self {
        var new = self;
        new.fg = color;
        return new;
    }

    /// Set the background color
    pub fn wbg(self: Self, color: Color) Self {
        var new = self;
        new.bg = color;
        return new;
    }

    /// Set bold style
    pub fn a_bold(self: Self) Self {
        var new = self;
        new.add_modifier.bold = true;
        return new;
    }

    /// Applies the dim (faint) modifier.
    pub fn a_dim(self: Self) Self {
        var new = self;
        new.add_modifier.dim = true;
        new.sub_modifier.dim = false;
        return new;
    }

    /// Applies the italic modifier.
    pub fn a_italic(self: Self) Self {
        var new = self;
        new.add_modifier.italic = true;
        new.sub_modifier.italic = false;
        return new;
    }

    /// Applies the underlined modifier.
    pub fn a_underlined(self: Self) Self {
        var new = self;
        new.add_modifier.underlined = true;
        new.sub_modifier.underlined = false;
        return new;
    }

    /// Applies the slow blink modifier.
    pub fn a_slow_blink(self: Self) Self {
        var new = self;
        new.add_modifier.slow_blink = true;
        new.sub_modifier.slow_blink = false;
        return new;
    }

    /// Applies the rapid blink modifier.
    pub fn a_rapid_blink(self: Self) Self {
        var new = self;
        new.add_modifier.rapid_blink = true;
        new.sub_modifier.rapid_blink = false;
        return new;
    }

    /// Applies the reversed (inverted colors) modifier.
    pub fn a_reversed(self: Self) Self {
        var new = self;
        new.add_modifier.reversed = true;
        new.sub_modifier.reversed = false;
        return new;
    }

    /// Applies the hidden (invisible text) modifier.
    pub fn a_hidden(self: Self) Self {
        var new = self;
        new.add_modifier.hidden = true;
        new.sub_modifier.hidden = false;
        return new;
    }

    /// Applies the crossed-out (strikethrough) modifier.
    pub fn a_crossed_out(self: Self) Self {
        var new = self;
        new.add_modifier.crossed_out = true;
        new.sub_modifier.crossed_out = false;
        return new;
    }

    // --- NEGATIVE BUILDERS (To cancel inheritance from a parent) ---

    /// Explicitly removes the bold modifier, overriding parent styles.
    pub fn s_bold(self: Self) Self {
        var new = self;
        new.sub_modifier.bold = true;
        new.add_modifier.bold = false;
        return new;
    }

    /// Explicitly removes the dim modifier, overriding parent styles.
    pub fn s_dim(self: Self) Self {
        var new = self;
        new.sub_modifier.dim = true;
        new.add_modifier.dim = false;
        return new;
    }

    /// Explicitly removes the italic modifier, overriding parent styles.
    pub fn s_italic(self: Self) Self {
        var new = self;
        new.sub_modifier.italic = true;
        new.add_modifier.italic = false;
        return new;
    }

    /// Explicitly removes the underlined modifier, overriding parent styles.
    pub fn s_underlined(self: Self) Self {
        var new = self;
        new.sub_modifier.underlined = true;
        new.add_modifier.underlined = false;
        return new;
    }

    /// Explicitly removes the slow blink modifier, overriding parent styles.
    pub fn s_slow_blink(self: Self) Self {
        var new = self;
        new.sub_modifier.slow_blink = true;
        new.add_modifier.slow_blink = false;
        return new;
    }

    /// Explicitly removes the rapid blink modifier, overriding parent styles.
    pub fn s_rapid_blink(self: Self) Self {
        var new = self;
        new.sub_modifier.rapid_blink = true;
        new.add_modifier.rapid_blink = false;
        return new;
    }

    /// Explicitly removes the reversed modifier, overriding parent styles.
    pub fn s_reversed(self: Self) Self {
        var new = self;
        new.sub_modifier.reversed = true;
        new.add_modifier.reversed = false;
        return new;
    }

    /// Explicitly removes the hidden modifier, overriding parent styles.
    pub fn s_hidden(self: Self) Self {
        var new = self;
        new.sub_modifier.hidden = true;
        new.add_modifier.hidden = false;
        return new;
    }

    /// Explicitly removes the crossed-out modifier, overriding parent styles.
    pub fn s_crossed_out(self: Self) Self {
        var new = self;
        new.sub_modifier.crossed_out = true;
        new.add_modifier.crossed_out = false;
        return new;
    }

    /// Merges another style into this one.
    /// Colors frome `other` overwrite colors from `self`.
    /// `add_modifier` from `other` are added, and `sub_modifier` are removed.
    pub fn patch(self: Self, other: Self) Self {
        var new = self;

        if (other.fg != null) new.fg = other.fg;
        if (other.bg != null) new.bg = other.bg;

        const self_add: u16 = @bitCast(self.add_modifier);
        const other_add: u16 = @bitCast(other.add_modifier);
        const other_sub: u16 = @bitCast(other.sub_modifier);

        new.add_modifier = @bitCast((self_add | other_add) & ~other_sub);

        const self_sub: u16 = @bitCast(self.sub_modifier);
        new.sub_modifier = @bitCast((self_sub | other_sub) & ~other_add);

        return new;
    }
};

test "Style builder pattern" {
    const style = Style.init().wfg(.Red).wbg(.Black).a_bold();

    try std.testing.expectEqual(Color.Red, style.fg.?);
}

test "Style patching" {
    const base = Style.init().wfg(.Blue).wbg(.Black).a_bold();

    const modifier = Style.init().wfg(.Red).a_italic().s_bold();

    const patched = base.patch(modifier);

    try std.testing.expectEqual(Color.Red, patched.fg.?);
    try std.testing.expectEqual(Color.Black, patched.bg.?);
    try std.testing.expectEqual(false, patched.add_modifier.bold);
    try std.testing.expectEqual(true, patched.add_modifier.italic);
}
