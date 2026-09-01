# Dot Lua API

This document is the reference for the public Lua API of the **dot** editor.

The API lives in a single global table `dot`, organised as small, focused
namespaces. Each namespace is also a regular Lua module, so you can either use
the global directly:

```lua
dot.ui.notify("Hello !")
dot.buf.open("scratch")
```

or `require` a namespace when you prefer explicit imports:

```lua
local ui = require("dot.ui")
ui.notify("Hello !")
```

> The whole API is **1-indexed**. Rows and columns always start at `1`.
> Screen positions use `{ x, y }` where `x` is the column and `y` is the row.

---

## Table of contents

- [Conventions](#conventions)
  - [Coordinates](#coordinates)
  - [Colors & styles](#colors--styles)
  - [Options tables](#options-tables)
  - [Errors](#errors)
  - [Modes](#modes)
  - [Events / hooks](#events--hooks)
- [Namespaces](#namespaces)
  - [`dot.ui` — drawing & notifications](#dotui--drawing--notifications)
  - [`dot.buf` — buffers](#dotbuf--buffers)
  - [`dot.edit` — editing the active buffer](#dotedit--editing-the-active-buffer)
  - [`dot.cmd` — the command line & commands](#dotcmd--the-command-line--commands)
  - [`dot.mode` — editor modes](#dotmode--editor-modes)
  - [`dot.keymap` — key mappings](#dotkeymap--key-mappings)
  - [`dot.hook` — events](#dothook--events)
  - [`dot.fs` — file system](#dotfs--file-system)
  - [`dot.sys` — system processes](#dotsys--system-processes)
  - [`dot.ts` — Tree-sitter](#dotts--tree-sitter)
  - [`dot.timer` — timers](#dottimer--timers)
  - [`dot.style` — colors & style presets](#dotstyle--colors--style-presets)
  - [`dot.log` — colored notifications](#dotlog--colored-notifications)
  - [`dot.debug` — introspection](#dotdebug--introspection)
- [Migration guide (old → new API)](#migration-guide-old--new-api)

---

## Conventions

### Coordinates

- **Buffers**: `row` / `col`, both 1-indexed. A range is inclusive on both ends:
  `buf:lines(2, 4)` returns rows 2, 3 and 4.
- **Screen**: a window is described by `{ x, y }` where `x` is the column and
  `y` is the row of its top-left corner.

### Colors & styles

Styles are plain Lua tables:

```lua
{ fg = "#FF0000", bg = "#2E3440", bold = true, italic = true, underline = true }
```

- `fg` / `bg` accept either an **8-bit ANSI index** (`0`–`255`) or a hex string
  `"#RRGGBB"`.
- All modifiers are booleans and optional.
- The style table is accepted **everywhere** a style is needed: notifications,
  ghosts, highlights, popups...

`dot.style` provides a palette and helpers (see below).

### Options tables

Most "complex" functions take a single options table instead of a long list of
positional arguments. Every field is **optional** and has a sensible default:

```lua
dot.ui.ghost({ row = 4, col = 1, text = "warning: unused variable", style = { fg = "#BF616A" } })
```

### Errors

- Getters return `nil` when there is nothing to return (no buffer, no AST...).
- Invalid user input raises a Lua error (`error("...")`) with an explanatory
  message. In command callbacks this is caught and shown as a toast by `dot.cmd`.
- `dot.buf.open(name)` never fails: it creates the buffer if it does not exist.

### Modes

Mode names returned by `dot.mode.get()` are the full names: `"Normal"`,
`"Insert"`, `"Command"`, `"Search"`.

`dot.mode.set()` accepts the full name **or** the single-letter abbreviation,
lower or upper case: `"n"`, `"N"`, `"normal"`, `"i"`, `"insert"`...

### Events / hooks

Events are identified by camel-case names (`"BufInit"`, `"CmdTab"`, ...). See the
[events catalogue](#events--hooks-1). A hook callback returns `true` to prevent
the editor's default behaviour for that event.

---

## Namespaces

### `dot.ui` — drawing & notifications

Everything that draws on the screen.

| Function | Description |
| --- | --- |
| `ui.notify(text, opts?)` | shows a transient toast (bottom-right corner) |
| `ui.toast(text, opts?)` | alias of `notify` |
| `ui.popup(opts)` | creates a bordered popup → `Popup` |
| `ui.ghost(opts)` | injects a virtual line under a buffer row (LSP hints…) |
| `ui.clear_ghosts()` | removes all ghost lines |
| `ui.highlight(opts)` | colors a range of the **active** buffer → extmark |
| `ui.clear_highlight(ns)` | removes all extmarks of a namespace |
| `ui.pum.show(opts)` | opens the popup completion menu |
| `ui.pum.hide()` | closes the popup completion menu |
| `ui.win.size()` | returns the terminal size |
| `ui.win.split(dir)` | splits the active panel (`"h"` or `"v"`) |
| `ui.cursor.get()` | returns `{ row, col }` (1-indexed) |
| `ui.cursor.set(row, col?)` | moves the cursor |
| `ui.canvas(w, h)` | creates a sub-pixel Braille canvas |
| `ui.gauge(value, max, width)` | builds a progress-bar string |

#### `notify`

```lua
dot.ui.notify("File saved !", { fg = "#A3BE8C", duration = 2000 })
```

`opts`:
- `fg`, `bg` — colors (see [Colors & styles](#colors--styles))
- `bold`, `italic`, `underline` — booleans
- `duration` — lifetime in ms (default `3000`)

Use `dot.log` for the preset variants (info / success / warn / error).

#### `popup`

```lua
local p = dot.ui.popup({ text = "Did you mean :help ?", duration = 4000 })
p:set_text("updated content")
p:close()
```

`opts`:
- `text` — the content (may contain `\n`, centered)
- `pos` — `{ x, y }`, defaults to the middle of the screen
- `size` — `{ x, y }` width/height, defaults to fit the text
- `duration` — lifetime in ms (`nil` = stays until `popup:close()`)

Methods:
- `popup:set_text(text)` replaces the content.
- `popup:close()` removes the popup immediately.

#### `ghost`

```lua
dot.ui.ghost({
  row = 12, col = 2,                        -- buffer coordinates
  text = "missing semicolon",
  prefix = "└── ",                          -- optional decorations
  style = { fg = "#F14C4C", italic = true },
})
```

Ghost lines are drawn *below* their buffer row without touching the buffer
content. Remove them all with `dot.ui.clear_ghosts()`.

#### `highlight`

```lua
-- table form
dot.ui.highlight({ row = 3, col = 1, len = 5, ns = 3, style = { fg = "#81A1C1", underline = true }, priority = 100 })

-- positional form (still allowed)
dot.ui.highlight(3, 3, 1, 5, { fg = "#81A1C1" }, 100)
```

`opts` fields: `row`, `col`, `len` (number of characters), `ns` (namespace id,
default `0`), `style` (default `{}`), `priority` (default `50`).
`ns` and `priority` let namespaces (tree-sitter, LSP, search…) coexist and
override each other predictably. Use `clear_highlight(ns)` to wipe a namespace.

#### `pum`

```lua
dot.ui.pum.show({
  x = 10, y = nil,                     -- default: right under the cursor
  items = {                            -- strings or richer items
    "hello", { text = "world", icon = "󰈙", icon_color = "#81A1C1" },
  },
  selected = 1,                        -- 1-indexed, default 1
})
dot.ui.pum.hide()
```

The menu grows *upward* from `y`. `icon_color` accepts a color as usual.

#### `palette`

A full-screen-ish command palette that replaces the native command line. When
opened it captures every keystroke (via the `CmdOpen` hook) until closed.

```lua
local pal = dot.ui.palette.open({
  title   = "COMMAND PALETTE",
  rows    = { "dashboard", "wq", "q" },   -- initial rows
  on_enter = function(selected, text) end, -- optional custom action
  on_input = function(input) end,          -- optional, called per keystroke
})
dot.ui.palette.close()                    -- close programmatically
dot.ui.palette.active()                   -- is a palette open?
```

- Typing filters the rows; `Up`/`Down` move the highlight (`▶`), `Enter` selects,
  `Escape` cancels and returns to Normal mode.
- `Tab` / `Shift-Tab` autocomplete:
  - `cmd <arg>` input → the last token is completed as a **path** (directories
    via `dot.fs.read_dir`, `open`/`source`/`write`/… all work). A single match is
    inserted immediately; several matches cycle on each `Tab` (`Shift-Tab` cycles
    back) and a `[n/m]` counter is shown next to the input. Directories keep their
    trailing `/` so `Tab` can descend into them.
  - bare command input → the command name is completed against `dot.cmd.list()`.
- Without `on_enter`, the default action runs the selected entry as a command:
  first through `dot.cmd.execute`, falling back to the native command engine.
- `rows` entries may also be tables `{ text, fg, bg, bold, italic, underline,
  marker, marker_fg }` for fully styled rows.
- The palette is drawn by the popup engine: centered bordered modal, `background`
  fill, `accent` border/indicator color.

#### `win`

```lua
local rows, cols = dot.ui.win.size()          -- or: local size = dot.ui.win.size() → size[1]=rows, size[2]=cols
dot.ui.win.split("v")                          -- split the active panel vertically
dot.ui.win.split("h")                          -- or horizontally
```

#### `cursor`

```lua
local row, col = dot.ui.cursor.get()           -- 1-indexed
dot.ui.cursor.set(5)                           -- jump to row 5, column 1
dot.ui.cursor.set(5, 30)                       -- jump to row 5, column 30
```

#### `canvas`

Sub-pixel Braille canvas for graphs/plots. Pure Lua, no screen access — build
strings and put them in a buffer or popup.

```lua
local c = dot.ui.canvas(24, 4)                 -- width, height in cells
c:set_pixel(1, 1)
c:line(0, 0, 20, 8)
c:plot({ 3, 5, 4, 8, 7 })                     -- smoothed curve from data
local rows = c:lines()                         -- array of Braille strings
```

#### `gauge`

```lua
local bar = dot.ui.gauge(3.2, 5, 20)           -- ████████░░░░░░░░░░░░
```

### `dot.buf` — buffers

| Function | Description |
| --- | --- |
| `buf.active()` | returns the `Buffer` of the active panel |
| `buf.find(name)` | returns `Buffer` or `nil` |
| `buf.open(name)` | returns an existing buffer, or creates it |

#### `Buffer`

Returned by `buf.active()`, `buf.find()` and `buf.open()`.

| Method | Description |
| --- | --- |
| `buf:name()` | filename / virtual name (`"*Messages*"`) |
| `buf:lines(start?, stop?)` | array of lines (defaults: whole buffer) |
| `buf:set_lines(start, stop, lines)` | replaces `[start..stop]` with `lines` |
| `buf:append(text)` | appends `text` + newline at the end |
| `buf:clear()` | empties the buffer |
| `buf:cursor()` / `buf:cursor(row, col)` | getter **and** setter |
| `buf:highlight(opts)` / `buf:clear_highlight(ns)` | extmarks on *this* buffer |
| `buf:show()` | displays the buffer in the active panel (read-only) |
| `buf:is_readonly()` | `true` if displayed by a read-only panel |
| `buf:save()` | writes the buffer to its file |

```lua
local msg = dot.buf.open("*Messages*")
msg:clear()
msg:append("first line")
msg:append("second line")

msg:set_lines(1, 2, { "replaced", "content" })
local lines = msg:lines(1, 2)           -- { "replaced", "content" }

msg:cursor(1, 1)
local r, c = msg:cursor()               -- 1, 1
```

Notes:
- `set_lines` with identical `start`/`stop` inserts without deleting
  (`buf:set_lines(2, 2, { "inserted" })`).
- `highlight` accepts the same table form as `dot.ui.highlight` but applies to
  the target buffer.
- `buf:show()` switches the active panel to the buffer and scrolls to the top.

### `dot.edit` — editing the active buffer

| Function | Description |
| --- | --- |
| `edit.insert(text)` | inserts text at the cursor (undoable) |
| `edit.move_right()` | moves the cursor one column right |

```lua
dot.edit.insert("const std = @import(\"std\");\n")
```

### `dot.cmd` — the command line & commands

| Function | Description |
| --- | --- |
| `cmd.input()` | current command-line text |
| `cmd.set_input(text)` | replaces the command-line text |
| `cmd.create(name, fn)` | registers a user command |
| `cmd.list()` | all command names (built-in + user) |
| `cmd.execute(name, args?)` | runs a registered user command; returns `true` if found, `false` to fall through |
| `cmd.history` | list of previously entered commands |

```lua
dot.cmd.create("hello", function(args)
  dot.ui.notify("Hello, " .. (args or "world"))
end)

dot.cmd.set_input("hello dot")
local what = dot.cmd.input()

-- Run a registered command programmatically (e.g. from a palette/callback).
local handled = dot.cmd.execute("hello", "dot")
```

`cmd.create` callbacks receive the argument string (possibly `""`). The callback
may return `true` to keep the command line open.

### `dot.mode` — editor modes

| Function | Description |
| --- | --- |
| `mode.get()` | `"Normal"`, `"Insert"`, `"Command"`, `"Search"` |
| `mode.set(name)` | accepts full or abbreviated names |

```lua
if dot.mode.get() == "Normal" then
  dot.mode.set("insert")
end
```

### `dot.keymap` — key mappings

```lua
dot.keymap.set("n", "<C-s>", function()
  dot.sys.save()
  dot.log.success("File saved !")
end)
```

- `mode` — `"n"`, `"i"`, `"c"`, `"v"` (normal / insert / command / search).
- `key` — e.g. `"<C-s>"`, `"dd"`, `"<Tab>"`.
- The callback runs when the sequence is typed; returning `true` prevents the
  default behaviour.

### `dot.hook` — events

```lua
dot.hook.on("BufInit", function()
  local active = dot.buf.active()
  if active and active:name():match("%.zig$") then
    dot.ts.load("zig", parsers .. "/zig.so", queries .. "/zig/highlights.scm")
  end
  return false
end)
```

Events are fired at the moments listed in the [events catalogue](#events--hooks-1).
Reading the buffer inside a hook gives you the state *after* the event.

### `dot.fs` — file system

```lua
local entries = dot.fs.read_dir("src/")        -- { "main.zig", "view/", ... }
local here = dot.fs.read_dir()                 -- current directory
```

Directories are returned with a trailing `/`.

### `dot.sys` — system processes

| Function | Description |
| --- | --- |
| `sys.spawn(cmd, callback)` | runs a command in the background |
| `sys.server.start(cmd, on_message)` → `id` | starts a long-running process |
| `sys.server.send(id, message)` | writes to the process stdin |
| `sys.server.stop(id)` | kills the process |
| `sys.save()` | saves the active buffer |

```lua
dot.sys.spawn("grep -rn TODO src", function(ok, output)
  dot.log.ok(ok and "found" or "grep failed")
end)

local zls = dot.sys.server.start("zls", function(ok, chunk)
  -- chunk is a slice of stdout
end)
dot.sys.server.send(zls, "Content-Length: 0\r\n\r\n")
dot.sys.server.stop(zls)
```

- `spawn` callback: `(success: boolean, output: string|nil)`.
- `server.on_message` callback: `(alive: boolean, chunk: string|nil)`.
- `send` payloads must include their own framing / line endings.

### `dot.ts` — Tree-sitter

| Function | Description |
| --- | --- |
| `ts.load(name, lib_path, query_path)` | loads a language for the active buffer |
| `ts.parse()` | returns the S-expression of the current AST (or `nil`) |

```lua
dot.ts.load("c", home .. "/.config/dot/parsers/c.so", home .. "/.config/dot/queries/c/highlights.scm")
local ast = dot.ts.parse()
```

### `dot.timer` — timers

| Function | Description |
| --- | --- |
| `timer.every(ms, fn)` | calls `fn` every `ms` milliseconds |
| `timer.after(ms, fn)` | calls `fn` once after `ms` milliseconds |

```lua
dot.timer.every(50, function() render_dashboard(dot.buf.find("*Dashboard*")) end)
dot.timer.after(1000, function() dot.ui.notify("One second elapsed") end)
```

`timer.after` is a convenience wrapper; the callback runs on the editor thread,
never concurrently with another timer callback.

### `dot.style` — colors & style presets

| Member | Description |
| --- | --- |
| `style.colors` | a table of named colors (hex strings) |
| `style.rgb(r, g, b)` | `"#RRGGBB"` string |
| `style.names` | `{ red = "#BF616A", ... }` (same as `colors` aliases) |

```lua
local accent = dot.style.colors.blue            -- "#81A1C1"
dot.ui.notify("styled", { fg = dot.style.rgb(129, 161, 193) })
```

### `dot.log` — colored notifications

```lua
dot.log.info("Dot is ready.")
dot.log.success("Saved !")
dot.log.warn("Uncommitted changes")
dot.log.error("Command failed")
```

Each maps to `dot.ui.notify` with a preset style and duration. Toasts stack in
the bottom-right corner, above the status line, and expire automatically.

### `dot.debug` — introspection

```lua
local info = dot.debug.info()
print(info.fps, info.mem_kb, info.queue_size)
```

`info` fields: `fps`, `timestamp`, `mem_kb`, `queue_size`, `buffers`
(indexed list of `{ filename, len, logical_size, gap_start, gap_end }`),
`views` (indexed list of `{ buf_idx, x, y, width, height, is_active,
is_readonly }`), `actions` (recent action names as strings).

---

## Events catalogue

| Event | Fired when |
| --- | --- |
| `BufInit` | a buffer is opened / created |
| `BufOpen` | a file is opened from disk |
| `BufWritePre` | before saving (return `true` to cancel) |
| `ModeChanged` | the editor mode changed |
| `CmdOpen` | command line opened (press `:`) — used to open the palette |
| `CmdEnter` | the command line is submitted |
| `CmdTab` / `CmdSTab` | Tab / Shift-Tab in the command line |
| `CmdBackspace` | backspace in the command line |
| `CmdEsc` | escape in the command line |
| `Up` / `Down` / `Left` / `Right` | arrow keys |
| `BackSpace` | backspace in insert mode |
| `SpaceInsert` | space character in insert mode |

`BufWritePre`, `CmdTab`, `CmdEnter`, `CmdEsc`, `CmdBackspace` and the arrow keys
hot keys honour the `prevent-default` contract: returning `true` overrides the
built-in behaviour. The other events are informational.

---

## Migration guide (old → new API)

| Old (removed) | New |
| --- | --- |
| `dot.print(msg, style)` | `dot.ui.notify(msg, opts)` |
| `dot.insert(text)` | `dot.edit.insert(text)` |
| `dot.move_right()` | `dot.edit.move_right()` |
| `dot.get_cursor()` | `dot.ui.cursor.get()` |
| `dot.get_lines(a, b)` | `dot.buf.active():lines(a, b)` |
| `dot.set_lines(a, b, lines)` | `dot.buf.active():set_lines(a, b, lines)` |
| `dot.hook_on(ev, fn)` | `dot.hook.on(ev, fn)` |
| `dot.show_pum(x, y, items, sel)` | `dot.ui.pum.show({ x, y, items, selected })` |
| `dot.hide_pum()` | `dot.ui.pum.hide()` |
| `dot.get_cmdline()` | `dot.cmd.input()` |
| `dot.set_cmdline(t)` | `dot.cmd.set_input(t)` |
| `dot.get_win_size()` | `dot.ui.win.size()` |
| `dot.add_style(ns, r, c, l, s, p)` | `dot.buf.active():highlight({ ns, row, col, len, style, priority })` |
| `dot.clear_style(ns)` | `dot.buf.active():clear_highlight(ns)` |
| `dot.add_buffer_style(id, ns, ...)` | `dot.buf.find/open(name):highlight(...)` |
| `dot.clear_buffer_style(id, ns)` | `buffer:clear_highlight(ns)` |
| `dot.spawn(cmd, cb)` | `dot.sys.spawn(cmd, cb)` |
| `dot.start_server(cmd, cb)` | `dot.sys.server.start(cmd, cb)` |
| `dot.server_send(id, msg)` | `dot.sys.server.send(id, msg)` |
| `dot.get_mode()` | `dot.mode.get()` |
| `dot.set_mode(m)` | `dot.mode.set(m)` |
| `dot.get_file()` | `dot.buf.active():name()` |
| `dot.add_ghost(r, c, t, p, s)` | `dot.ui.ghost({ row, col, text, prefix, style })` |
| `dot.clear_ghosts()` | `dot.ui.clear_ghosts()` |
| `dot.set_keymap(m, k, fn)` | `dot.keymap.set(m, k, fn)` |
| `dot.save_current_file()` | `dot.sys.save()` |
| `dot.get_native_cmds()` | `dot.cmd.list()` |
| `dot.jump_to(row)` | `dot.ui.cursor.set(row)` |
| `dot.hsplit()` / `dot.vsplit()` | `dot.ui.win.split("h" / "v")` |
| `dot.ts_load_language(n, l, q)` | `dot.ts.load(n, l, q)` |
| `dot.ts_parse()` | `dot.ts.parse()` |
| `dot.create_buffer(name)` | `dot.buf.open(name)` |
| `dot.get_buffer_by_name(name)` | `dot.buf.find(name)` |
| `dot.set_view_buffer(id)` | `buffer:show()` |
| `dot.append_to_buffer(id, t)` | `buffer:append(t)` |
| `dot.set_buffer_lines(id, ...)` | `buffer:set_lines(...)` |
| `dot.set_buffer_cursor(id, r, c)` | `buffer:cursor(r, c)` |
| `dot.clear_buffer(id)` | `buffer:clear()` |
| `dot.get_debug_info()` | `dot.debug.info()` |
| `dot.set_interval(ms, fn)` | `dot.timer.every(ms, fn)` |
| `dot.std.log` | `dot.log` |
| `dot.std.buf` | methods on `dot.buf` / `Buffer` |
| `dot.core.commands` | `dot.cmd` |
| `dot.core.keymaps` | `dot.keymap` |