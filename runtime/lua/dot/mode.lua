---@class dot.mode
local M = {}

---Aliases accepted by `set` (full name or abbreviation, case-insensitive).
local aliases = {
	n = "n", normal = "n",
	i = "i", insert = "i",
	c = "c", command = "c",
	s = "v", v = "v", search = "v",
}

---Current mode: "Normal", "Insert", "Command" or "Search".
---@return string mode
function M.get()
	return _dot.get_mode()
end

---Switches mode. Accepts "n"/"normal", "i"/"insert", "c"/"command",
---"s"/"search" (and the legacy "v" alias for search).
---@param name string
function M.set(name)
	if type(name) ~= "string" then
		error("dot.mode.set: expected a string")
	end
	local key = aliases[name:lower()]
	if not key then
		error("dot.mode.set: unknown mode '" .. name .. "'")
	end
	_dot.set_mode(key)
end

return M