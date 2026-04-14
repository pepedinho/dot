local M = {}

local registry = {}

M.create = function(name, callback)
	registry[name] = callback
end

M.get_all = function()
	local list = {}
	local native_cmds = dot.get_native_cmds()
	if native_cmds then
		for _, cmd_name in ipairs(native_cmds) do
			table.insert(list, cmd_name)
		end
	end

	for name, _ in pairs(registry) do
		table.insert(list, name)
	end

	table.sort(list)
	return list
end

dot.hook_on("CmdEnter", function()
	local cmd_line = dot.get_cmdline()
	local cmd_name, args = cmd_line:match("^%s*(%S+)%s*(.*)$")

	if not cmd_name then
		return false
	end

	if registry[cmd_name] then
		local ok, err = pcall(registry[cmd_name], args)
		if not ok then
			dot.print("Error: cmd: [" .. cmd_name .. "]: " .. tostring(err))
		end
		dot.set_cmdline("")
		dot.set_mode("n")
		return true
	end
	return false
end)

return M
