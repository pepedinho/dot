local M = {}
local cmd = require("dot.commands")

local function open_messages()
	local buf_id = dot.get_buffer_by_name("*Messages*")
	if not buf_id then
		dot.print("no messages found")
		return
	end

	dot.hsplit()
	dot.set_view_buffer(buf_id)
end

cmd.create("messages", open_messages)

return M
