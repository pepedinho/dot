---@class dot.edit
local M = {}

---Inserts text at the logical cursor position of the active buffer.
---Consecutive insertions are grouped for undo.
---@param text string
function M.insert(text)
	_dot.insert(tostring(text))
end

---Moves the logical cursor one character to the right.
function M.move_right()
	_dot.move_right()
end

return M