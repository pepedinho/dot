---@class dot.log
local M = {}
local style = require("dot.style")

---Info notification (blue).
---@param text string
function M.info(text)
	_dot.print(text, style.toast.info)
end

---Success notification (green).
---@param text string
function M.success(text)
	_dot.print(text, style.toast.success)
end

---Warning notification (yellow).
---@param text string
function M.warn(text)
	_dot.print(text, style.toast.warn)
end

---Error notification (red).
---@param text string
function M.error(text)
	_dot.print(text, style.toast.error)
end

---@alias dot.log.levels "info"|"success"|"warn"|"error"

---Dispatch to `info`, `success`, `warn` or `error`.
---@param level dot.log.levels
---@param text string
function M.log(level, text)
	if M[level] then
		M[level](text)
	end
end

return M