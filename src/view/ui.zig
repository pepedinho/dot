const std = @import("std");
const zui = @import("zui");
const Editor = @import("../core/core.zig").Editor;

pub fn renderEditor(editor: *Editor, frame: *zui.terminal.Frame) void {
    const screen = frame.size();

    // 1. Découpage principal : Éditeur (Haut) | Command Line (Bas)
    const chunks = zui.layout.Layout.init(&.{
        .{ .Fill = 1 }, // Zone des buffers (Views)
        .{ .Length = 1 }, // Zone de commande
    }).dir(.Vertical).split(frame.allocator, screen) catch return;

    // 2. Rendu des fenêtres de code
    renderViews(editor, frame, chunks[0]);

    // 3. Rendu de la barre de statut et des popups (à faire plus tard)
    // renderStatusLine(editor, frame, chunks[1]);
    // renderPopups(editor, frame);

    // 4. PLACEMENT DU CURSEUR
    // C'est ici qu'on fait le lien entre la logique de 'dot' et l'affichage de 'zui'
    if (editor.mode == .Command or editor.mode == .Search) {
        // En mode commande, le curseur est en bas, après le texte tapé
        const prompt_len = 1; // ':' ou '/'
        const cmd_len = editor.cmd_buf.items.len;
        frame.setCursor(@as(u16, @intCast(prompt_len + cmd_len)), chunks[1].y);
    } else {
        // En mode normal/insert, le curseur est dans la vue active
        const view_area = chunks[0]; // C'est la zone où ton éditeur est réellement dessiné
        const view = editor.getActiveView();
        const pos = view.buf.getCursorPos();

        // Oublie view.x et view.y, utilise view_area.x et view_area.y !
        const screen_x = view_area.x + view.gutter_width + (pos.x - 1) - view.col_offset;
        const screen_y = view_area.y + (pos.y - 1) - view.row_offset;

        // Vérification de sécurité pour ne pas mettre le curseur dans la status bar ou le gutter
        if (screen_x >= view_area.x + view.gutter_width and
            screen_x < view_area.x + view_area.width and
            screen_y >= view_area.y and
            screen_y < view_area.y + view_area.height)
        {
            frame.setCursor(@as(u16, @intCast(screen_x)), @as(u16, @intCast(screen_y)));
        }
    }
}

fn renderViews(editor: *Editor, frame: *zui.terminal.Frame, area: zui.layout.Rect) void {
    var clear = zui.widgets.Clear{};
    clear.render(area, frame.buffer);
    const view = editor.getActiveView();

    const allocator = frame.allocator;
    var lines = allocator.alloc(zui.widgets.Line, view.height) catch return;

    var i: u16 = 0;
    while (i < view.height) : (i += 1) {
        const row_idx = i + view.row_offset;
        const line_text = view.buf.getLine(allocator, row_idx) catch "";

        var spans = allocator.alloc(zui.widgets.Span, 1) catch continue;
        spans[0] = .{
            .text = line_text,
            .style = .{},
        };

        lines[i] = .{ .spans = spans };
    }

    var para = zui.widgets.Paragraph{ .lines = lines, .wraping = true };
    para.render(area, frame.buffer);
}
