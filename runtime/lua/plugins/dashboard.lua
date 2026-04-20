local M = {}
local cmd = require("dot.commands")

local DASHBOARD_NS = 42
local tick_count = 0

local theme = {
	border = "#4C566A",
	title = "#88C0D0",
	accent = "#B48EAD",
	success = "#A3BE8C",
	warning = "#EBCB8B",
	error = "#BF616A",
	text = "#ECEFF4",
	muted = "#616E88",
	gauge_f = "#81A1C1",
	gauge_e = "#3B4252",
}

local function create_gauge(val, max, width)
	local fill_char = "█"
	local empty_char = "░"
	local ratio = math.min(math.max(val / max, 0), 1)
	local filled = math.floor(ratio * width)
	local empty = width - filled
	return string.rep(fill_char, filled) .. string.rep(empty_char, empty)
end

local function render_dashboard(buf_id)
	tick_count = tick_count + 1
	local debug_info = dot.get_debug_info()
	local mode = dot.get_mode()

	local spinners = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
	local spinner = spinners[(tick_count % #spinners) + 1]

	local lines = {}
	local styles = {}
	local current_row = 1

	local function add_line(text, hl)
		table.insert(lines, " " .. text)
		if hl then
			for _, style_def in ipairs(hl) do
				table.insert(
					styles,
					{ row = current_row, col = style_def.col + 1, len = style_def.len, style = style_def.style }
				)
			end
		end
		current_row = current_row + 1
	end

	local function add_separator()
		add_line(
			"├──────────────────────────────────────────────────┤",
			{ { col = 1, len = 52, style = { fg = theme.border } } }
		)
	end

	add_line(
		"╭──────────────────────────────────────────────────╮",
		{ { col = 1, len = 52, style = { fg = theme.border } } }
	)
	add_line(string.format("│  %s DOT ENGINE SYSTEM MONITOR                    │", spinner), {
		{ col = 1, len = 1, style = { fg = theme.border } },
		{ col = 4, len = 1, style = { fg = theme.accent, bold = true } },
		{ col = 6, len = 25, style = { fg = theme.title, bold = true } },
		{ col = 52, len = 1, style = { fg = theme.border } },
	})
	add_separator()

	local fps_color = debug_info.fps > 50 and theme.success or theme.error
	local mode_color = mode == "Normal" and theme.success or theme.warning

	add_line(
		string.format(
			"│  FPS : %-4d │ RAM : [%s] %-5d KB │",
			debug_info.fps,
			create_gauge(debug_info.mem_kb, 5000, 15),
			debug_info.mem_kb
		),
		{
			{ col = 1, len = 1, style = { fg = theme.border } },
			{ col = 10, len = 4, style = { fg = fps_color, bold = true } },
			{ col = 15, len = 1, style = { fg = theme.border } },
			{ col = 26, len = 15, style = { fg = theme.gauge_f } },
			{ col = 43, len = 5, style = { fg = theme.text } },
			{ col = 52, len = 1, style = { fg = theme.border } },
		}
	)

	add_line(string.format("│  MODE: %-4s │ QUEUE : %-25d │", mode, debug_info.queue_size), {
		{ col = 1, len = 1, style = { fg = theme.border } },
		{ col = 10, len = #mode, style = { fg = mode_color, bold = true } },
		{ col = 15, len = 1, style = { fg = theme.border } },
		{ col = 27, len = 25, style = { fg = theme.text } },
		{ col = 52, len = 1, style = { fg = theme.border } },
	})
	add_separator()

	add_line(string.format("│  🗂️ BUFFERS (%d)                                  │", #debug_info.buffers), {
		{ col = 1, len = 1, style = { fg = theme.border } },
		{ col = 7, len = 12, style = { fg = theme.accent, bold = true } },
		{ col = 52, len = 1, style = { fg = theme.border } },
	})
	for i, b in ipairs(debug_info.buffers) do
		local line = string.format(
			"│  [%d] %-15s %5db | Gap: %d->%d      ",
			i,
			string.sub(b.filename, 1, 15),
			b.len,
			b.gap_start,
			b.gap_end
		)
		line = line .. string.rep(" ", 52 - #line) .. "│"
		add_line(line, {
			{ col = 1, len = 1, style = { fg = theme.border } },
			{ col = 4, len = 3, style = { fg = theme.muted } },
			{ col = 8, len = #b.filename, style = { fg = theme.text } },
			{ col = 52, len = 1, style = { fg = theme.border } },
		})
	end
	add_separator()

	add_line(string.format("│  🖥️ VIEWS (%d)                                    │", #debug_info.views), {
		{ col = 1, len = 1, style = { fg = theme.border } },
		{ col = 7, len = 10, style = { fg = theme.accent, bold = true } },
		{ col = 52, len = 1, style = { fg = theme.border } },
	})
	for i, v in ipairs(debug_info.views) do
		local active_mark = v.is_active and "★" or " "
		local ro_mark = v.is_readonly and "[RO]" or ""
		local line = string.format(
			"│  [%d]%s Buf:%-2d | %dx%d | Pos:%d,%d %s",
			i,
			active_mark,
			v.buf_idx,
			v.width,
			v.height,
			v.x,
			v.y,
			ro_mark
		)
		line = line .. string.rep(" ", 52 - #line) .. "│"
		add_line(line, {
			{ col = 1, len = 1, style = { fg = theme.border } },
			{ col = 7, len = 1, style = { fg = v.is_active and theme.success or theme.muted } },
			{ col = 52, len = 1, style = { fg = theme.border } },
		})
	end
	add_separator()

	add_line(string.format("│  ⚡ ACTION QUEUE (%d)                              │", #debug_info.actions), {
		{ col = 1, len = 1, style = { fg = theme.border } },
		{ col = 7, len = 17, style = { fg = theme.accent, bold = true } },
		{ col = 52, len = 1, style = { fg = theme.border } },
	})
	if #debug_info.actions == 0 then
		add_line("│  (empty)                                           │", {
			{ col = 1, len = 1, style = { fg = theme.border } },
			{ col = 4, len = 7, style = { fg = theme.muted, italic = true } },
			{ col = 52, len = 1, style = { fg = theme.border } },
		})
	else
		for i, act in ipairs(debug_info.actions) do
			local line = string.format("│  - %-46s│", act)
			add_line(line, {
				{ col = 1, len = 1, style = { fg = theme.border } },
				{ col = 6, len = #act, style = { fg = theme.warning } },
				{ col = 52, len = 1, style = { fg = theme.border } },
			})
		end
	end
	add_line(
		"╰──────────────────────────────────────────────────╯",
		{ { col = 1, len = 52, style = { fg = theme.border } } }
	)

	dot.set_buffer_lines(buf_id, 1, 999, lines)
	dot.set_buffer_cursor(buf_id, 1, 1)

	dot.clear_buffer_style(buf_id, DASHBOARD_NS)
	for _, s in ipairs(styles) do
		dot.add_buffer_style(buf_id, DASHBOARD_NS, s.row, s.col, s.len, s.style, 100)
	end
end

local function open_dashboard()
	local buf_id = dot.get_buffer_by_name("*Dashboard*")
	if not buf_id then
		buf_id = dot.create_buffer("*Dashboard*")

		dot.set_interval(100, function()
			local current_id = dot.get_buffer_by_name("*Dashboard*")
			if current_id then
				render_dashboard(current_id)
			end
		end)
	end

	dot.vsplit()
	dot.set_view_buffer(buf_id)
	render_dashboard(buf_id)
end

cmd.create("dashboard", open_dashboard)

return M
