---@class dot.keymap
local M = {}

---Maps a key sequence to a Lua callback in a mode.
---@param mode string "n", "i", "c" or "v" (normal / insert / command / search).
---@param key string e.g. "<C-s>", "dd", "<Tab>".
---@param callback fun() Function to run.
function M.set(mode, key, callback)
	if type(mode) ~= "string" or type(key) ~= "string" or type(callback) ~= "function" then
		error("dot.keymap.set(mode, key, callback): invalid arguments")
	end
	_dot.set_keymap(mode, key, callback)
end

return M