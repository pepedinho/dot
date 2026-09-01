---@meta dot
-- Definition file for the public Dot Lua API (`dot.*`).
-- The `dot` global is assembled at runtime by `runtime/lua/dot/init.lua`
-- from the `_dot.*` primitives. Do not execute this file directly.

---@class dot
---@field ui dot.ui UI helpers: toasts, popups, highlights, PUM, cursor, canvas.
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

---@return dot dot
return dot