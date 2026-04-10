dot.print("formating...")

local cursor = dot.get_cursor()
local current_row = cursor[1]

local lines = dot.get_lines(current_row, 99999)

if #lines > 0 then
	local new_lines = {}
	for i, line in ipairs(lines) do
		table.insert(new_lines, "// AUTO COMMENT" .. string.upper(line))
	end

	dot.set_lines(current_row, 99999, new_lines)
	dot.print("formatting finished !")
else
	dot.print("failed to read")
end
