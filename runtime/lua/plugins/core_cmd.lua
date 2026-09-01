local M = {}

local function sh(c)
	if not c or c == "" then
		dot.ui.notify("usage: sh <cmd>")
	end

	dot.sys.spawn(c, function(success, output)
		if not success then
			dot.log.error("Command failed")
		else
			dot.log.success("Command finished")
		end

		if output and output ~= "" then
			local buffer = dot.buf.open("*Shell Output*")
			buffer:clear()
			buffer:append("\n--- " .. c .. " ---")
			buffer:append(output)
		end
	end)
end

dot.cmd.create("sh", sh)

return M