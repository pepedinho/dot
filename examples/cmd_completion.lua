local is_menu_open = false
local current_matches = {}
local selected_index = 0
local current_dir = ""
local cmd_offset = 10
local prev_path = ""

dot.hook_on("CmdTab", function()
	local cmd = dot.get_cmdline()
	local cmd_type, type_path = string.match(cmd, "^(%w+)%s+(.*)$")

	if cmd_type == "open" then
		if not is_menu_open then
			current_dir = string.match(type_path, "^(.*[/\\])") or ""
			local prefix = string.sub(type_path, #current_dir + 1)

			local files = dot.read_dir(current_dir)

			current_matches = {}
			for _, filename in ipairs(files) do
				if string.sub(filename, 1, #prefix) == prefix then
					table.insert(current_matches, filename)
				end
			end

			table.sort(current_matches)
			if #current_matches == 0 then
				return true
			end

			if #current_matches == 1 then
				dot.set_cmdline(cmd_type .. " " .. current_dir .. current_matches[1])
				return true
			end

			prev_path = type_path
			is_menu_open = true
			selected_index = 0
		else
			if prev_path == type_path then
				selected_index = selected_index + 1
				if selected_index >= #current_matches then
					selected_index = 0
				end
			else
				dot.hide_pum()
				is_menu_open = false
				return false
			end
		end
		local win = dot.get_win_size()
		local row = win[1]
		local col = string.len(cmd) + cmd_offset
		dot.print("current y = " .. row .. "| current x = " .. col)
		dot.show_pum(col, row - 1, current_matches, selected_index)
		return true
	end
end)

dot.hook_on("CmdEnter", function()
	if is_menu_open then
		local chosen_file = current_matches[selected_index + 1]
		local cmd_type = string.match(dot.get_cmdline(), "^(%w+)%s+")

		dot.set_cmdline(cmd_type .. " " .. current_dir .. chosen_file)
		dot.hide_pum()
		is_menu_open = false
		return true
	end
end)

dot.hook_on("CmdBackspace", function()
	if is_menu_open then
		dot.hide_pum()
		is_menu_open = false
	end
end)

dot.hook_on("CmdEsc", function()
	if is_menu_open then
		dot.hide_pum()
		is_menu_open = false
	end
end)
