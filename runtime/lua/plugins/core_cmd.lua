local M = {}
local cmd = require("dot.commands")

local function sh(c)
	if not c or c == "" then
		dot.print("usage: sh <cmd>")
	end

	-- local line = "bash -c " .. '"' .. c .. '"'
	-- dot.print("debug: " .. line)
	dot.spawn(c, function(success, output)
		if not success then
			dot.print("cmd failed !")
		end
		dot.print(output)
	end)
end

cmd.create("sh", sh)
