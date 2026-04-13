const Editor = @import("core.zig").Editor;

pub fn loadStandardKeyBinds(editor: *Editor) !void {
    try editor.registerKeyBind(.Normal, "i", .{ .SetMode = .Insert });
    try editor.registerKeyBind(.Normal, "h", .MoveLeft);
    try editor.registerKeyBind(.Normal, "j", .MoveDown);
    try editor.registerKeyBind(.Normal, "k", .MoveUp);
    try editor.registerKeyBind(.Normal, "l", .MoveRight);
    try editor.registerKeyBind(.Normal, "a", .Append);
    try editor.registerKeyBind(.Normal, "o", .AppendNewLine);
    try editor.registerKeyBind(.Normal, "x", .DeleteChar);
    // try editor.registerKeyBind(.Normal, "q", .Quit);
    try editor.registerKeyBind(.Normal, ":", .{ .SetMode = .Command });
    try editor.registerKeyBind(.Normal, "/", .{ .SetMode = .Search });
    try editor.registerKeyBind(.Normal, "n", .NextSearchResult);
    try editor.registerKeyBind(.Normal, "N", .PrevSearchResult);
    try editor.registerKeyBind(.Normal, "u", .Undo);
    try editor.registerKeyBind(.Normal, "y", .YankLine);
    try editor.registerKeyBind(.Normal, "p", .Paste);
    try editor.registerKeyBind(.Normal, "w", .EOW);
}
