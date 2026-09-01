local State = {
	is_open = false,
	matches = {},
	selected_index = 0,
	base_prefix = "",
	prev_input = "",
	offset = 10,
}

local colors = {
	blue = "#81A1C1",
	green = "#A3BE8C",
	yellow = "#EBCB8B",
	magenta = "#B48EAD",
	white = "#ECEFF4",
}

local function get_file_info(filename)
	if filename:match("[/\\]$") then
		return "", colors.blue
	end
	local ext = filename:match("^.+(%..+)$") or ""
	if ext == ".lua" then
		return "", colors.blue
	end
	if ext == ".zig" then
		return "", colors.yellow
	end
	if ext == ".c" then
		return "", colors.white
	end
	return "", colors.white
end

local function close_pum()
	if State.is_open then
		dot.ui.pum.hide()
		State.is_open = false
		State.matches = {}
	end
end

local function get_command_completions(input)
	local available_cmds = dot.cmd.list()
	local matches = {}

	for _, cmd_name in ipairs(available_cmds) do
		if cmd_name:sub(1, #input) == input then
			table.insert(matches, {
				text = cmd_name,
				icon = "",
				icon_color = colors.magenta,
			})
		end
	end
	return matches, ""
end

local function get_file_completions(cmd_type, type_path)
	local current_dir = string.match(type_path, "^(.*[/\\])") or ""
	local prefix = string.sub(type_path, #current_dir + 1)
	local files = dot.fs.read_dir(current_dir)
	local matches = {}

	for _, filename in ipairs(files) do
		if string.sub(filename, 1, #prefix) == prefix then
			local icon_char, icon_col = get_file_info(filename)
			table.insert(matches, {
				text = filename,
				icon = icon_char,
				icon_color = icon_col,
			})
		end
	end

	table.sort(matches, function(a, b)
		return a.text < b.text
	end)

	local base_prefix = cmd_type .. " " .. current_dir
	return matches, base_prefix
end

local function handle_tab(direction)
	local input = dot.cmd.input()

	if State.is_open then
		if State.prev_input == input then
			State.selected_index = (State.selected_index + direction + #State.matches) % #State.matches

			local win = dot.ui.win.size()
			dot.ui.pum.show({
				x = string.len(input) + State.offset,
				y = win[1] - 1,
				items = State.matches,
				selected = State.selected_index + 1,
			})
			return true
		else
			close_pum()
			return false
		end
	end

	local matches = {}
	local base_prefix = ""
	local cmd_type, type_path = string.match(input, "^(%w+)%s+(.*)$")

	if cmd_type and (cmd_type == "open" or cmd_type == "source") then
		matches, base_prefix = get_file_completions(cmd_type, type_path)
	else
		local pure_cmd = input:match("^(%w*)$")
		if pure_cmd then
			matches, base_prefix = get_command_completions(pure_cmd)
		end
	end

	if #matches == 0 then
		return true
	end

	if #matches == 1 then
		dot.cmd.set_input(base_prefix .. matches[1].text)
		return true
	end

	State.prev_input = input
	State.is_open = true
	State.matches = matches

	State.selected_index = (direction > 0) and 0 or (#matches - 1)
	State.base_prefix = base_prefix

	local win = dot.ui.win.size()
	dot.ui.pum.show({
		x = string.len(input) + State.offset,
		y = win[1] - 1,
		items = State.matches,
		selected = State.selected_index + 1,
	})
	return true
end

dot.hook.on("CmdTab", function()
	return handle_tab(1)
end)

dot.hook.on("CmdSTab", function()
	return handle_tab(-1)
end)

dot.hook.on("CmdEnter", function()
	if State.is_open then
		local chosen_text = State.matches[State.selected_index + 1].text

		dot.cmd.set_input(State.base_prefix .. chosen_text)

		close_pum()
		return true
	end
end)

dot.hook.on("CmdBackspace", close_pum)
dot.hook.on("CmdEsc", close_pum)