local M = {}

dot.hook.on("CmdOpen", function()
	if dot.ui.palette.active() then
		return false
	end
	dot.ui.palette.open({
		title = "COMMAND PALETTE",
		background = "#1E232E",
		accent = "#8BE9FD",
	})
	return false
end)

return M