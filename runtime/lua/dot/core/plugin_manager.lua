local M = {}

M.setup = function(user_plugins)
	local loaded = 0

	for plugin_name, is_enabled in pairs(user_plugins) do
		if is_enabled then
			local ok, err = pcall(require, "plugins." .. plugin_name)
			if ok then
				loaded = loaded + 1
			else
				dot.ui.notify("plugin: [" .. plugin_name .. "] failed to load")
				dot.ui.notify("err: " .. tostring(err), { fg = "#FFFFFF", bg = "#BF616A" })
			end
		end
	end

	if loaded > 0 then
		dot.ui.notify("dot: " .. loaded .. "/" .. #user_plugins .. " plugins loaded !")
	end
end

return M