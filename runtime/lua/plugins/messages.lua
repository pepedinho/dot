local M = {}

local function open_messages()
	local buffer = dot.buf.open("*Messages*")
	dot.ui.win.split("h")
	buffer:show()
end

dot.cmd.create("messages", open_messages)
dot.cmd.create("shell", function()
	local buffer = dot.buf.open("*Shell Output*")
	dot.ui.win.split("h")
	buffer:show()
end)

return M