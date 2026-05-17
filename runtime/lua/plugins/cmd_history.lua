local cmd_lib = require("dot.core.commands")
local index = 1

dot.print("cmds_history loaded ! ")

dot.hook_on("Up", function()
	if dot.get_mode() == "Command" then
		local cmds_history = cmd_lib.history
		if #cmds_history == 0 then
			return false
		end
		if index == 0 then
			index = #cmds_history
		else
			index = index - 1
		end

		if index < 1 then
			index = #cmds_history
		end

		dot.set_cmdline(cmds_history[index])
		return true
	end
	return false
end)
