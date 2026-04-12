local M = {}

M.setup = function(user_plugins)
	local loaded = 0

	for plugin_name, is_enabled in pairs(user_plugins) do
		if is_enabled then
			local ok, err = pcall(require, "plugins." .. plugin_name)
			if ok then
				loaded = loaded + 1
			else
				dot.print("Error: plugin: [" .. plugin_name .. "] Failed to load")
			end
		end
	end

	if loaded > 0 then
		dot.print("dot: " .. loaded .. "/" .. #user_plugins .. " plugins loaded !")
	end
end

return M
