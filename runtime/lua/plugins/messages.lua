local M = {}
local cmd = require("dot.core.commands")
local buf = require("dot.std.buf")

local function open_messages()
	local buf_id = buf.open_virtual_hsplit("*Messages*")
	if not buf_id then
		dot.print("no messages found")
		return
	end
end

cmd.create("messages", open_messages)
cmd.create("shell", function()
	buf.open_virtual_hsplit("*Shell Output*")
end)

return M
