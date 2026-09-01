---@class dot.timer
local M = {}

---Calls `fn` every `ms` milliseconds.
---@param ms integer Interval in milliseconds.
---@param fn fun()
function M.every(ms, fn)
	if type(ms) ~= "number" or type(fn) ~= "function" then
		error("dot.timer.every(ms, fn): invalid arguments")
	end
	_dot.set_interval(ms, fn)
end

---Calls `fn` once, `ms` milliseconds from now.
---@param ms integer Delay in milliseconds.
---@param fn fun()
function M.after(ms, fn)
	if type(ms) ~= "number" or type(fn) ~= "function" then
		error("dot.timer.after(ms, fn): invalid arguments")
	end
	local done = false
	_dot.set_interval(ms, function()
		if done then
			return
		end
		done = true
		fn()
	end)
end

return M