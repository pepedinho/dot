---@class dot.hook
local M = {}

---Registers a callback for an editor event.
---Returning `true` from the callback prevents the default behaviour.
---@param event_name string e.g. "BufWritePre", "CmdTab", "ModeChanged".
---@param callback fun():boolean?
function M.on(event_name, callback)
	if type(event_name) ~= "string" or type(callback) ~= "function" then
		error("dot.hook.on(event, callback): invalid arguments")
	end
	_dot.hook_on(event_name, callback)
end

return M