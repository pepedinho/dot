---@meta
-- Definition file for the Dot Lua API.
-- Do not execute this file. It is solely used for LSP autocompletion.

---@class DotApi
dot = {}

---@class PumItem
---@field text string The main text of the item.
---@field icon? string (Optional) A graphical unicode icon (e.g., Nerd Font).
---@field icon_color? string (Optional) ANSI color code for icon.

---@alias DotColor integer|string

---@class DotStyle
---@field fg? DotColor Foreground color
---@field bg? DotColor Background color
---@field bold? boolean
---@field italic? boolean
---@field underline? boolean
---@field duration? integer Duration in milliseconds (used for toasts)

---Displays a temporary notification (Toast) in the bottom right corner of the screen.
---@param message string The notification text to display.
---@param style? DotStyle (Optional) Visual theme and duration of the toast.
function dot.print(message, style) end

---Inserts text at the current logical cursor position.
---Multiple consecutive insertions are grouped in the history for Undo functionality.
---@param text string The text to insert.
function dot.insert(text) end

---Moves the logical cursor one character to the right.
function dot.move_right() end

---Retrieves the current logical cursor position.
---@return integer[] # A table containing {row, column} (1-indexed).
function dot.get_cursor() end

---Give the actual terminal win size
---@return integer[] # A table containing {row, column} (1-indexed).
function dot.get_win_size() end

---Retrieves an array containing the requested lines of text from the active buffer.
---@param start_row integer Starting row (inclusive, 1-indexed).
---@param end_row integer Ending row (inclusive).
---@return string[] # An array of strings representing the lines.
function dot.get_lines(start_row, end_row) end

---Replaces a block of lines in the current buffer.
---To insert lines without deleting any, `start_row` and `end_row` must be identical.
---@param start_row integer Starting row of the deletion block.
---@param end_row integer Ending row of the deletion block.
---@param lines string[] An array of strings containing the new lines to insert.
function dot.set_lines(start_row, end_row, lines) end

---Replaces a block of lines in the <id> buffer.
---To insert lines without deleting any, `start_row` and `end_row` must be identical.
---@param buf_id integer Id of the targeted buffer
---@param start_row integer Starting row of the deletion block.
---@param end_row integer Ending row of the deletion block.
---@param lines string[] An array of strings containing the new lines to insert.
function dot.set_buffer_lines(buf_id, start_row, end_row, lines) end

---Registers a callback function for a specific editor event.
---If the callback returns `true`, the editor's default behavior is prevented (Prevent Default).
---@param event_name string The name of the event (e.g., "BufWritePre", "CmdTab", "CmdEnter").
---@param callback fun():boolean? The function to execute when the event is triggered.
function dot.hook_on(event_name, callback) end

---Retrieves the current text content of the command line (prompt).
---@return string # The text typed by the user.
function dot.get_cmdline() end

---Replaces the text content of the command line.
---@param text string The new command line text.
function dot.set_cmdline(text) end

---Opens a directory and lists the files and folders it contains.
---@param path string The directory path (use an empty string "" for the current working directory).
---@return string[] # An array containing the names of files and directories.
function dot.read_dir(path) end

---Displays the Popup Menu (PUM) on the screen for autocomplétion or selection.
---@param x integer The X position (column) where the menu should be drawn.
---@param y integer The Y position (row) where the menu should be drawn (the menu expands upwards).
---@param items (string|PumItem)[] The array of choices to display. Can be strings or tables with text and icon.
---@param selected_index integer The index of the highlighted item (Note: 0-indexed to match the Zig backend).
function dot.show_pum(x, y, items, selected_index) end

---Hides and clears the active Popup Menu (PUM).
function dot.hide_pum() end

---Applies a visual style to a portion of text.
---@param id integer The style namespace
---@param row integer The line (1-indexed)
---@param col integer The starting column (1-indexed)
---@param length integer The number of characters to color
---@param style DotStyle Style definition
---@param prio integer Priority of the style, Default 50 when omitted
function dot.add_style(id, row, col, length, style, prio) end

---Cleans all style from the active buffer with the provided id.
function dot.clear_style(id) end

---Executes a system command in the background without blocking the editor.
---@param cmd string The command to execute (e.g., "grep -r TODO .")
---@param callback fun(success: boolean, output: string?) The function called at the end.
function dot.spawn(cmd, callback) end

---Starts a persistent background process (e.g., an LSP server) and listens to its standard output.
---The process runs continuously until killed or until the editor closes.
---@param cmd string The system command to execute (e.g., "zls").
---@param on_message fun(success: boolean, output: string?) Callback triggered every time the process writes to its stdout.
---@return integer # The unique Server ID used to communicate with this process.
function dot.start_server(cmd, on_message) end

---Sends a text payload to the standard input (stdin) of a running background process.
---@param server_id integer The unique ID of the server (returned by `dot.start_server`).
---@param message string The data to send (must include necessary line endings like \n or \r\n).
function dot.server_send(server_id, message) end

---Return current editor mode
---@return string # Current editor mode
function dot.get_mode() end

---Return current filename or "" if is anonymous buffer
---@return string # Current editor mode
function dot.get_file() end

---Injects a virtual "Ghost Line" directly into the editor view below a specific line.
---Used to display LSP diagnostics or inline hints without modifying the actual buffer.
---@param row integer The line number under which the ghost line will appear (1-indexed).
---@param col integer The column offset for indentation (1-indexed).
---@param text string The main text to display (e.g., the error message).
---@param prefix string? An optional prefix string (e.g., "└── ").
---@param style DotStyle The formatting style.
function dot.add_ghost(row, col, text, prefix, style) end

---Clears all currently active Ghost Lines from the editor view.
function dot.clear_ghosts() end
---Add keymap to editor
---@param mode string The editor mode targeted 'n' 'i' 'c' ...
---@param key string They key triggered callback
---@param callback function The callback function which be called by dot
function dot.set_keymap(mode, key, callback) end

--- Save current buffer into it associated file
function dot.save_current_file() end

--- Return list of dot native command
--- @return table
function dot.get_native_cmds() end

--- change editor mode to target mode parameter ("n, i, c,...")
--- @param mode string The editor mode targeted 'n' 'i' 'c' ...
function dot.set_mode(mode) end

--- Jump to row line
--- @param row integer The target line
function dot.jump_to(row) end

--- Split current window horizontaly with the same buffer
function dot.hsplit() end

--- Split current window verticaly with the same buffer
function dot.vsplit() end

--- Return Ast for the current buffer
function dot.ts_parse() end

--- load language grammar for treesitter
--- @param name string Name of the file
--- @param lib string Path to the .so file
--- @param query string Path to the highlights scm file
function dot.ts_load_language(name, lib, query) end

--- Creates a new gap buffer with the specified filename/name and adds it to the editor's buffer list.
--- Useful for creating virtual buffers (e.g., "*Messages*", "*NetRW*").
---@param name string The name or virtual filename of the new buffer.
---@return integer buf_id The unique ID (index) of the newly created buffer.
function dot.create_buffer(name) end

--- Searches the editor's active buffers for one matching the given name.
---@param name string The name or virtual filename to search for.
---@return integer|nil buf_id The ID of the buffer if found, otherwise `nil`.
function dot.get_buffer_by_name(name) end

--- Changes the currently active view (pane) to display the buffer associated with `buf_id`.
--- It automatically scrolls to the bottom and sets the view to read-only mode.
---@param buf_id integer The ID of the target buffer to display.
function dot.set_view_buffer(buf_id) end

--- Appends text directly to the end of a specific buffer without modifying the current cursor position or active view.
--- Automatically appends a newline character at the end of the inserted text.
---@param buf_id integer The ID of the target buffer.
---@param text string The text content to append.
function dot.append_to_buffer(buf_id, text) end

---Moves the cursor to a specific logical position within a given buffer.
---@param buf_id integer The ID of the target buffer.
---@param row integer The target row (1-indexed).
---@param col integer The target column (1-indexed).
function dot.set_buffer_cursor(buf_id, row, col) end

---Applies a visual style to a specific range of text within a given buffer.
---@param buf_id integer The ID of the target buffer.
---@param ns_id integer The namespace ID for the style (e.g., to separate Tree-sitter from Search).
---@param row integer The row number (1-indexed).
---@param col integer The starting column (1-indexed).
---@param length integer The number of characters to color.
---@param style DotStyle The style definition (fg, bg, bold, italic, underline).
---@param priority? integer The Z-index priority of the style (higher overwrites lower, default is 50).
function dot.add_buffer_style(buf_id, ns_id, row, col, length, style, priority) end

---Clears all styles associated with a specific namespace within a given buffer.
---@param buf_id integer The ID of the target buffer.
---@param ns_id integer The namespace ID to clear.
function dot.clear_buffer_style(buf_id, ns_id) end

---@class DebugBuffer
---@field logical_size integer
---@field gap_start integer
---@field gap_end integer
---@field len integer
---@field filename string

---@class DebugView
---@field buf_idx integer
---@field is_active boolean
---@field x integer
---@field y integer
---@field width integer
---@field height integer
---@field is_readonly boolean

---@class DebugInfo
---@field fps integer
---@field timestamp integer
---@field mem_kb integer
---@field queue_size integer
---@field buffers DebugBuffer[]
---@field views DebugView[]
---@field actions string[]

---Returns comprehensive debugging information about the editor's internal state.
---@return DebugInfo
function dot.get_debug_info() end

---Executes a callback function repeatedly at a specified interval.
---@param interval_ms integer The interval in milliseconds.
---@param callback function The Lua function to execute.
function dot.set_interval(interval_ms, callback) end
