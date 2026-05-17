---@meta dot.dashboard
local M = {}
local cmd = require("dot.core.commands")
local ui = require("dot.ui")

local DASHBOARD_NS = 42

local fps_history = {}
local history_length = 60
local elapsed_time = 0
local last_timestamp = 0

local theme = {
	border = "#4C566A",
	title = "#88C0D0",
	accent = "#B48EAD",
	success = "#A3BE8C",
	warning = "#EBCB8B",
	error = "#BF616A",
	text = "#ECEFF4",
	muted = "#616E88",
	graph_f = "#A3BE8C",
	gauge_f = "#81A1C1",
}

local function render_dashboard(buf_id)
	local debug_info = dot.get_debug_info()
	local mode = dot.get_mode()

	if last_timestamp == 0 then
		last_timestamp = debug_info.timestamp
	end
	local delta_time = (debug_info.timestamp - last_timestamp) / 1000.0
	last_timestamp = debug_info.timestamp
	elapsed_time = elapsed_time + delta_time

	table.insert(fps_history, debug_info.fps)
	if #fps_history > history_length then
		table.remove(fps_history, 1)
	end

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

	-- --- HEADER ---
	add_line(
		"╭──────────────────────────────────────────────────╮",
		{ { col = 1, len = 52, style = { fg = theme.border } } }
	)
	add_line("│  ⚡ DOT ENGINE SYSTEM MONITOR                    │", {
		{ col = 1, len = 1, style = { fg = theme.border } },
		{ col = 4, len = 1, style = { fg = theme.warning, bold = true } },
		{ col = 6, len = 25, style = { fg = theme.title, bold = true } },
		{ col = 52, len = 1, style = { fg = theme.border } },
	})
	add_separator()

	local graph_w, graph_h = 24, 4
	local graph_canvas = ui.new_braille_canvas(graph_w, graph_h)
	local animated_history = {}

	for i = 1, #fps_history do
		local wave = math.sin((elapsed_time * 5.0) + (i * 0.2)) * 3.0
		animated_history[i] = fps_history[i] + wave
	end

	graph_canvas:plot_smooth_curve(animated_history)
	local graph_lines = graph_canvas:to_utf8_lines()

	local fps_color = debug_info.fps > 50 and theme.success or (debug_info.fps > 30 and theme.warning or theme.error)
	local mode_color = mode == "Normal" and theme.success or theme.warning

	for i = 1, graph_h do
		local line = "│  "
		if i == 1 then
			line = line .. string.format("FPS   : %-6d", debug_info.fps)
		elseif i == 2 then
			line = line .. string.format("MODE  : %-6s", mode)
		elseif i == 3 then
			line = line .. string.format("QUEUE : %-6d", debug_info.queue_size)
		else
			line = line .. "              "
		end

		line = line .. "  ╭" .. graph_lines[i] .. "╮      │"

		local hls = {
			{ col = 1, len = 1, style = { fg = theme.border } },
			{ col = 52, len = 1, style = { fg = theme.border } },
		}
		if i == 1 then
			table.insert(hls, { col = 13, len = 4, style = { fg = fps_color, bold = true } })
		end
		if i == 2 then
			table.insert(hls, { col = 13, len = #mode, style = { fg = mode_color, bold = true } })
		end

		table.insert(hls, { col = 17, len = 1, style = { fg = theme.muted } })
		table.insert(hls, { col = 18, len = graph_w, style = { fg = theme.graph_f } })
		table.insert(hls, { col = 18 + graph_w, len = 1, style = { fg = theme.muted } })

		add_line(line, hls)
	end
	add_separator()

	-- --- MEMORY ---
	local ram_gauge = ui.create_gauge(debug_info.mem_kb, 5000, 20)
	add_line(string.format("│  RAM   : [%s] %-5d KB         │", ram_gauge, debug_info.mem_kb), {
		{ col = 1, len = 1, style = { fg = theme.border } },
		{ col = 12, len = 20, style = { fg = theme.gauge_f } },
		{ col = 52, len = 1, style = { fg = theme.border } },
	})
	add_separator()

	-- --- ENTITIES ---
	add_line(
		string.format(
			"│  🗂️ BUFFERS: %-3d          🖥️ VIEWS: %-3d            │",
			#debug_info.buffers,
			#debug_info.views
		),
		{
			{ col = 1, len = 1, style = { fg = theme.border } },
			{ col = 4, len = 2, style = { fg = theme.accent } },
			{ col = 16, len = 3, style = { fg = theme.text, bold = true } },
			{ col = 29, len = 2, style = { fg = theme.accent } },
			{ col = 39, len = 3, style = { fg = theme.text, bold = true } },
			{ col = 52, len = 1, style = { fg = theme.border } },
		}
	)
	add_separator()

	-- --- ACTIONS QUEUE ---
	add_line("│  ⚡ RECENT ACTIONS                               │", {
		{ col = 1, len = 1, style = { fg = theme.border } },
		{ col = 4, len = 1, style = { fg = theme.warning } },
		{ col = 6, len = 14, style = { fg = theme.muted, bold = true } },
		{ col = 52, len = 1, style = { fg = theme.border } },
	})

	local max_actions = math.min(#debug_info.actions, 4)
	if max_actions == 0 then
		add_line("│    (empty)                                       │", {
			{ col = 1, len = 1, style = { fg = theme.border } },
			{ col = 5, len = 7, style = { fg = theme.muted, italic = true } },
			{ col = 52, len = 1, style = { fg = theme.border } },
		})
	else
		for i = 1, max_actions do
			local act = debug_info.actions[i]
			add_line(string.format("│    - %-42s│", act), {
				{ col = 1, len = 1, style = { fg = theme.border } },
				{ col = 7, len = #act, style = { fg = theme.text } },
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
		dot.add_buffer_style(buf_id, DASHBOARD_NS, s.row, s.col, s.len, s.style, 50)
	end
end

local function open_dashboard()
	local buf_id = dot.get_buffer_by_name("*Dashboard*")
	if not buf_id then
		buf_id = dot.create_buffer("*Dashboard*")
		dot.set_interval(50, function()
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
