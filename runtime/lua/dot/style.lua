---@class dot.style
local M = {}

---Named color palette (Nord-inspired).
---@class dot.style.colors
M.colors = {
	bg = "#2E3440",
	fg = "#ECEFF4",
	red = "#BF616A",
	green = "#A3BE8C",
	yellow = "#EBCB8B",
	blue = "#81A1C1",
	magenta = "#B48EAD",
	cyan = "#88C0D0",
}

---Alias of `M.colors`.
M.names = M.colors

---Builds a "#RRGGBB" color string from components.
---@param r integer 0-255
---@param g integer 0-255
---@param b integer 0-255
---@return string color
function M.rgb(r, g, b)
	return string.format("#%02X%02X%02X", r, g, b)
end

---Notification presets (used by `dot.log`).
M.toast = {
	info = { fg = M.colors.fg, bg = M.colors.blue, duration = 3000 },
	success = { fg = M.colors.fg, bg = M.colors.green, bold = true, duration = 2500 },
	warn = { fg = M.colors.bg, bg = M.colors.yellow, bold = true, duration = 4000 },
	error = { fg = M.colors.fg, bg = M.colors.red, bold = true, duration = 5000 },
}

return M