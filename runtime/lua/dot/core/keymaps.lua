local M = {}

M.set = function(mode, key, callback)
	dot.set_keymap(mode, key, callback)
end

return M
