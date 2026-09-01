local index = 1

dot.ui.notify("cmds_history loaded ! ")

dot.hook.on("Up", function()
	if dot.mode.get() == "Command" then
		local cmds_history = dot.cmd.history
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

		dot.cmd.set_input(cmds_history[index])
		return true
	end
	return false
end)