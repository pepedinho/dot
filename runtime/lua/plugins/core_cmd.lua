local M = {}
local cmd = require("dot.core.commands")
local log = require("dot.std.log")
local buf = require("dot.std.buf")

local function sh(c)
	if not c or c == "" then
		dot.print("usage: sh <cmd>")
	end

	-- local line = "bash -c " .. '"' .. c .. '"'
	-- dot.print("debug: " .. line)
	dot.spawn(c, function(success, output)
		if not success then
			log.error("Command failed")
		else
			log.success("Command finished")
		end

		if output and output ~= "" then
			buf.clear_virtual("*Shell Output*")
			buf.append_virtual("*Shell Output*", "\n--- " .. c .. " ---")
			buf.append_virtual("*Shell Output*", output)
		end
	end)
end

cmd.create("sh", sh)

-- return M
