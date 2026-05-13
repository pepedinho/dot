local log = require("dot.std.log")
---@class DotBuf
local M = {}

---Add text at the end of a virtual buffer (create id not exist)
---@param name string name of virtual buffer
---@param text string content to add
---@return integer buf_id buffer ID
function M.append_virtual(name, text)
	local buf_id = dot.get_buffer_by_name(name)
	if not buf_id then
		buf_id = dot.create_buffer(name)
	end
	dot.append_to_buffer(buf_id, text)
	return buf_id
end

function M.open_virtual_hsplit(name)
	local buf_id = dot.get_buffer_by_name(name)
	if buf_id then
		dot.hsplit()
		dot.set_view_buffer(buf_id)
	else
		log.error("Buffer " .. name .. "does not exist")
	end
end

return M
