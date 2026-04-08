const Editor = @import("core.zig").Editor;

pub fn loadStandardKeyBinds(editor: *Editor) !void {
    try editor.registerKeyBind('i', .{ .SetMode = .Insert });
    try editor.registerKeyBind('h', .MoveLeft);
    try editor.registerKeyBind('j', .MoveDown);
    try editor.registerKeyBind('k', .MoveUp);
    try editor.registerKeyBind('l', .MoveRight);
    try editor.registerKeyBind('a', .Append);
    try editor.registerKeyBind('o', .AppendNewLine);
    try editor.registerKeyBind('x', .DeleteChar);
    try editor.registerKeyBind('q', .Quit);
    try editor.registerKeyBind(':', .{ .SetMode = .Command });
    try editor.registerKeyBind('/', .{ .SetMode = .Search });
    try editor.registerKeyBind('n', .NextSearchResult);
    try editor.registerKeyBind('N', .PrevSearchResult);
    try editor.registerKeyBind('u', .Undo);
}
