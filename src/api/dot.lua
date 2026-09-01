---@meta dot
-- Definition file for the public Dot Lua API (`dot.*`).
-- The `dot` global is assembled at runtime by `runtime/lua/dot/init.lua`
-- from the `_dot.*` primitives. Do not execute this file directly.

---@class dot
---@field ui dot.ui UI helpers: toasts, popups, highlights, PUM, cursor, canvas, palette.
---@field buf dot.buf Buffer management and the `Buffer` class.
---@field edit dot.edit Editing primitives (insert, cursor movement).
---@field cmd dot.cmd Command registry, history and command-line access.
---@field mode dot.mode Mode getters/setters with friendly aliases.
---@field keymap dot.keymap Keybinding registration.
---@field hook dot.hook Event hooks.
---@field fs dot.fs Filesystem helpers.
---@field sys dot.sys System commands, background servers and saving.
---@field ts dot.ts Tree-sitter integration.
---@field timer dot.timer Timers (`every` / `after`).
---@field style dot.style Color palette and toast presets.
---@field log dot.log Colored notifications (info/success/warn/error).
---@field debug dot.debug Editor introspection.
dot = {}

-- ============================================================
--  Shared types
-- ============================================================

---Color: 0-255 ANSI index or "#RRGGBB" hex string.
---@alias dot.style.color integer|string

---Formatting style: color + attributes.
---@class dot.style
---@field fg? dot.style.color
---@field bg? dot.style.color
---@field bold? boolean
---@field italic? boolean
---@field underline? boolean

---Entries of the popup menu.
---@class dot.ui.PumItem
---@field text string
---@field icon? string
---@field icon_color? dot.style.color

---A single styled row of the command palette.
---@class dot.ui.PaletteRow
---@field text string
---@field fg? dot.style.color
---@field bg? dot.style.color
---@field bold? boolean
---@field italic? boolean
---@field underline? boolean
---@field marker? string Marker printed before the text when highlighted.
---@field marker_fg? dot.style.color

---Options for `dot.ui.palette.open`.
---@class dot.ui.palette_opts
---@field title? string Title shown at the top of the palette.
---@field rows? (string|dot.ui.PaletteRow)[] Initial rows (defaults to all commands).
---@field background? dot.style.color Popup background fill.
---@field accent? dot.style.color Border + indicator color.
---@field on_enter? fun(selected: integer, text: string) Custom action on Enter.
---@field on_input? fun(input: string) Called whenever the input changes.
--
-- Tab / Shift-Tab in the palette autocomplete: `cmd <arg>` completes the path
-- (cycling through matches with a `[n/m]` counter), a bare name completes a
-- command from `dot.cmd.list()`.

---@class dot.ui.palette
---@field open fun(opts: dot.ui.palette_opts): table Open the palette.
---@field close fun(palette?: table) Close a palette (or the active one).
---@field active fun(): boolean True while a palette is open.

---@return dot dot
return dot