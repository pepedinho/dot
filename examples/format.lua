dot.ui.notify("formating...")

local cursor = dot.ui.cursor.get()
local current_row = cursor[1]

local active = dot.buf.active()
local lines = active:lines(current_row, 99999)

if #lines > 0 then
	local new_lines = {}
	for i, line in ipairs(lines) do
		table.insert(new_lines, "// AUTO COMMENT" .. string.upper(line))
	end

	active:set_lines(current_row, 99999, new_lines)
	dot.ui.notify("formatting finished !")
else
	dot.ui.notify("failed to read")
end