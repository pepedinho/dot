local cmd_lib = require("dot.core.commands")

local State = {
	is_open = false,
	matches = {},
	selected_index = 0,
	base_prefix = "",
	prev_input = "",
	offset = 10,
}

local colors = {
	blue = "\27[34m",
	green = "\27[32m",
	yellow = "\27[33m",
	magenta = "\27[35m",
	white = "\27[37m",
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
		dot.hide_pum()
		State.is_open = false
		State.matches = {}
	end
end

local function get_command_completions(input)
	local available_cmds = cmd_lib.get_all()
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
	local files = dot.read_dir(current_dir)
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

dot.hook_on("CmdTab", function()
	local input = dot.get_cmdline()

	if State.is_open then
		if State.prev_input == input then
			State.selected_index = (State.selected_index + 1) % #State.matches
			local win = dot.get_win_size()
			dot.show_pum(string.len(input) + State.offset, win[1] - 1, State.matches, State.selected_index)
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
		dot.set_cmdline(base_prefix .. matches[1].text)
		return true
	end

	State.prev_input = input
	State.is_open = true
	State.matches = matches
	State.selected_index = 0
	State.base_prefix = base_prefix

	local win = dot.get_win_size()
	dot.show_pum(string.len(input) + State.offset, win[1] - 1, State.matches, State.selected_index)
	return true
end)

dot.hook_on("CmdEnter", function()
	if State.is_open then
		local chosen_text = State.matches[State.selected_index + 1].text

		dot.set_cmdline(State.base_prefix .. chosen_text)

		close_pum()
		return true
	end
end)

dot.hook_on("CmdBackspace", close_pum)
dot.hook_on("CmdEsc", close_pum)
