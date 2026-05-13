local style = require("dot.std.style")
local M = {}

function M.info(msg)
	dot.print(msg, style.toast.info)
end

function M.success(msg)
	dot.print(msg, style.toast.success)
end

function M.warn(msg)
	dot.print(msg, style.toast.warn)
end

function M.error(msg)
	dot.print(msg, style.toast.error)
end

return M
