---@class DotStdStyle
local M = {}

---@class DotColors
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

---@class DotToastStyles
---@field info DotStyle
---@field success DotStyle
---@field warn DotStyle
---@field error DotStyle
M.toast = {
	info = { fg = M.colors.fg, bg = M.colors.blue, duration = 3000 },
	success = { fg = M.colors.bg, bg = M.colors.green, bold = true, duration = 2000 },
	warn = { fg = M.colors.bg, bg = M.colors.yellow, bold = true, duration = 4000 },
	error = { fg = M.colors.fg, bg = M.colors.red, bold = true, duration = 5000 },
}

return M
