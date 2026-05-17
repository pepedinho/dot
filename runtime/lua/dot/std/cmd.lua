local core_cmds = require("dot.core.commands")

---@class DotCmd
local M = {}

---Register a new user command
---@param name string name of the command
---@param  callback string func(args: string) function to execute
function M.create(name, callback)
	core_cmds.create(name, callback)
end

return M
