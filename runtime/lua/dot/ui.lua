---@class dot.ui
local M = {}
local style = require("dot.style")

---@class dot.ui.notify_opts
---@field fg? dot.style.color Foreground color
---@field bg? dot.style.color Background color
---@field bold? boolean
---@field italic? boolean
---@field underline? boolean
---@field duration? integer Lifetime in ms (default 3000)

---Shows a transient notification (toast) in the bottom-right corner.
---@param text string The message to display.
---@param opts? dot.ui.notify_opts
function M.notify(text, opts)
	_dot.print(tostring(text), opts or {})
end

---Alias of `notify`.
---@param text string
---@param opts? dot.ui.notify_opts
M.toast = M.notify

-- ============================================================
--  POPUPS
-- ============================================================

---@class dot.ui.Popup
---@field id integer
local Popup = {}
Popup.__index = Popup

---@class dot.ui.popup_opts
---@field text? string Content (may contain \n; centered)
---@field pos? integer[] Screen position { col, row } (default: middle)
---@field size? integer[] Size { width, height } (default: fits the text)
---@field duration? integer Lifetime in ms (omit to keep open until closed)

---Creates a bordered popup window.
---@param opts dot.ui.popup_opts
---@return dot.ui.Popup
function M.popup(opts)
	opts = opts or {}
	local id = _dot.popup(opts)
	if not id then
		error("dot.ui.popup: failed to create popup")
	end
	return setmetatable({ id = id }, Popup)
end

---Replaces the popup content.
---@param text string
---@return dot.ui.Popup self
function Popup:set_text(text)
	_dot.popup_set_text(self.id, tostring(text))
	return self
end

---Closes and removes the popup immediately.
function Popup:close()
	_dot.popup_close(self.id)
end

-- ============================================================
--  GHOST LINES
-- ============================================================

---@class dot.ui.ghost_opts
---@field row integer Buffer row under which the ghost is drawn (1-indexed).
---@field col integer Column offset for indentation (1-indexed).
---@field text string The main text.
---@field prefix? string Optional decoration (e.g. "└── ").
---@field style? table Formatting style (fg, bg, bold, italic, underline).

---Injects a virtual line below a buffer row (LSP hints, diagnostics...).
---@param opts dot.ui.ghost_opts
function M.ghost(opts)
	opts = opts or {}
	_dot.add_ghost(opts.row or 1, opts.col or 1, opts.text or "", opts.prefix, opts.style or {})
end

---Removes all ghost lines.
function M.clear_ghosts()
	_dot.clear_ghosts()
end

-- ============================================================
--  HIGHLIGHTS (extmarks on the active buffer)
-- ============================================================

---@class dot.ui.range_opts
---@field ns? integer Namespace id (default 0)
---@field row integer Row (1-indexed)
---@field col integer Starting column (1-indexed)
---@field len integer Number of characters
---@field style? table The style table
---@field priority? integer Higher overrides lower (default 50)

---Parses `highlight` arguments in table or positional form.
---@return integer ns, integer row, integer col, integer len, table st, integer priority
local function parse_range(...)
	local args = { ... }
	if type(args[1]) == "table" then
		local o = args[1]
		return o.ns or 0, o.row or 1, o.col or 1, o.len or 0, o.style or {}, o.priority or 50
	end
	return args[1] or 0, args[2] or 1, args[3] or 1, args[4] or 0, args[5] or {}, args[6] or 50
end

---Colors a range of the active buffer.
---@param ... dot.ui.range_opts | integer -- table form or (ns, row, col, len, style, priority)
function M.highlight(...)
	local ns, row, col, len, st, prio = parse_range(...)
	_dot.add_style(ns, row, col, len, st, prio)
end

---Removes all highlights of a namespace from the active buffer.
---@param ns integer
function M.clear_highlight(ns)
	_dot.clear_style(ns or 0)
end

-- ============================================================
--  POPUP MENU (PUM)
-- ============================================================

---@class dot.ui.PumItem
---@field text string
---@field icon? string
---@field icon_color? string

---@class dot.ui.pum_opts
---@field x? integer Column of the menu (left edge).
---@field y? integer Row the menu grows up from (default: under the cursor).
---@field items (string|dot.ui.PumItem)[] The choices.
---@field selected? integer 1-indexed selected item (default 1).

M.pum = {}

---Opens the completion menu (it grows upward from `y`).
---@param opts dot.ui.pum_opts
function M.pum.show(opts)
	opts = opts or {}
	local items = opts.items or {}
	if #items == 0 then
		return
	end
	local x = opts.x or 1
	local y = opts.y
	if not y then
		local size = _dot.get_win_size()
		local cursor = _dot.get_cursor()
		y = math.min(cursor[1] + 1, size[1])
	end
	_dot.show_pum(x, y, items, math.max(1, opts.selected or 1) - 1)
end

---Closes the completion menu.
function M.pum.hide()
	_dot.hide_pum()
end

-- ============================================================
--  WINDOW
-- ============================================================

M.win = {}

---Returns the terminal size: `{ rows, cols }` (1-indexed).
---@return integer[] size
function M.win.size()
	return _dot.get_win_size()
end

---Splits the active panel. `direction` is "h" (horizontal) or "v" (vertical).
---@param direction string
function M.win.split(direction)
	if direction == "v" or direction == "V" or direction == "vertical" then
		_dot.vsplit()
	else
		_dot.hsplit()
	end
end

-- ============================================================
--  CURSOR
-- ============================================================

M.cursor = {}

---Returns the cursor position `{ row, col }` (1-indexed).
---@return integer[] position
function M.cursor.get()
	return _dot.get_cursor()
end

---Moves the cursor. `col` defaults to 1.
---@param row integer
---@param col? integer
function M.cursor.set(row, col)
	local id = _dot.active_buffer()
	_dot.set_buffer_cursor(id, row, col or 1)
end

-- ============================================================
--  SUB-PIXEL BRAILLE CANVAS
-- ============================================================

local function bit_or(a, b)
	local res = 0
	local m = 1
	while a > 0 or b > 0 do
		local rem_a = a % 2
		local rem_b = b % 2
		if rem_a == 1 or rem_b == 1 then
			res = res + m
		end
		a = math.floor(a / 2)
		b = math.floor(b / 2)
		m = m * 2
	end
	return res
end

local function utf8_char(n)
	local f = math.floor
	if n <= 0x7f then
		return string.char(n)
	elseif n <= 0x7ff then
		return string.char(f(n / 64) + 192, n % 64 + 128)
	elseif n <= 0xffff then
		return string.char(f(n / 4096) + 224, f(n % 4096 / 64) + 128, n % 64 + 128)
	else
		return string.char(f(n / 262144) + 240, f(n % 262144 / 4096) + 128, f(n % 4096 / 64) + 128, n % 64 + 128)
	end
end

local SUB_IDX_MAP = {
	{ 0x01, 0x08 },
	{ 0x02, 0x10 },
	{ 0x04, 0x20 },
	{ 0x40, 0x80 },
}

---@class dot.ui.Canvas
---@field width integer
---@field height integer
local Canvas = {}
Canvas.__index = Canvas

---Creates a sub-pixel Braille canvas. Width/height are terminal cells:
---a canvas of `w x h` cells exposes `w*2` by `h*4` sub-pixels.
---@param width integer
---@param height integer
---@return dot.ui.Canvas
function M.canvas(width, height)
	local self = setmetatable({
		width = width,
		height = height,
		dots = {},
	}, Canvas)
	for i = 1, width * height do
		self.dots[i] = 0
	end
	return self
end

---Sets a single sub-pixel (1-indexed within the canvas sub-pixel space).
---@param px integer
---@param py integer
function Canvas:set_pixel(px, py)
	if px < 1 or px > self.width * 2 or py < 1 or py > self.height * 4 then
		return
	end

	local cell_x = math.floor((px - 1) / 2)
	local cell_y = math.floor((py - 1) / 4)
	local cell_idx = (cell_y * self.width) + cell_x + 1

	local sub_x = (px - 1) % 2
	local sub_y = (py - 1) % 4

	local mask = SUB_IDX_MAP[sub_y + 1][sub_x + 1]
	self.dots[cell_idx] = bit_or(self.dots[cell_idx], mask)
end

---Draws a line between two sub-pixels (Bresenham).
---@param x0 integer
---@param y0 integer
---@param x1 integer
---@param y1 integer
function Canvas:line(x0, y0, x1, y1)
	local dx = math.abs(x1 - x0)
	local dy = math.abs(y1 - y0)
	local sx = x0 < x1 and 1 or -1
	local sy = y0 < y1 and 1 or -1
	local err = dx - dy

	while true do
		self:set_pixel(x0, y0)
		if x0 == x1 and y0 == y1 then
			break
		end
		local e2 = 2 * err
		if e2 > -dy then
			err = err - dy
			x0 = x0 + sx
		end
		if e2 < dx then
			err = err + dx
			y0 = y0 + sy
		end
	end
end

---Plots a smoothed curve from an array of values.
---@param data number[]
function Canvas:plot(data)
	local canvas_p_width = self.width * 2
	local canvas_p_height = self.height * 4

	local data_length = #data
	if data_length == 0 then
		return
	end

	local min_val, max_val = data[1], data[1]
	for i = 1, data_length do
		if data[i] < min_val then
			min_val = data[i]
		end
		if data[i] > max_val then
			max_val = data[i]
		end
	end

	if min_val == max_val then
		min_val = min_val - 1
		max_val = max_val + 1
	end

	local last_x, last_y = nil, nil

	for px = 1, canvas_p_width do
		local data_idx = math.floor((px - 1) * (data_length - 1) / (canvas_p_width - 1)) + 1
		local val = data[data_idx] or 0

		local ratio = (val - min_val) / (max_val - min_val)
		local py = math.floor(canvas_p_height - (ratio * (canvas_p_height - 1)))

		if last_x and last_y then
			local dist_x = px - last_x
			local dist_y = py - last_y
			local steps = math.max(math.abs(dist_x), math.abs(dist_y))

			for s = 0, steps do
				local s_x = math.floor(last_x + (dist_x * s / steps))
				local s_y = math.floor(last_y + (dist_y * s / steps))
				self:set_pixel(s_x, s_y)
			end
		else
			self:set_pixel(px, py)
		end

		last_x, last_y = px, py
	end
end

---Converts the canvas into an array of Braille strings.
---@return string[] lines
function Canvas:lines()
	local lines = {}
	local base_code = 0x2800

	for y = 0, self.height - 1 do
		local line_chars = ""
		for x = 0, self.width - 1 do
			local cell_idx = (y * self.width) + x + 1
			local dot_mask = self.dots[cell_idx]
			line_chars = line_chars .. utf8_char(base_code + dot_mask)
		end
		table.insert(lines, line_chars)
	end
	return lines
end

-- ============================================================
--  MISC DRAWING HELPERS
-- ============================================================

---Builds a progress bar string. Example: `███░░░░░`.
---@param value number Current value.
---@param max number Maximum value.
---@param width integer Width in cells.
---@return string bar
function M.gauge(value, max, width)
	local fill_char = "█"
	local empty_char = "░"
	local ratio = math.min(math.max(value / max, 0), 1)
	local filled = math.floor(ratio * width)
	return string.rep(fill_char, filled) .. string.rep(empty_char, width - filled)
end

---Rotates a 3D point around X, Y and Z axes.
---@param x number
---@param y number
---@param z number
---@param ax number Radians
---@param ay number Radians
---@param az number Radians
---@return number x, number y, number z
function M.rotate3d(x, y, z, ax, ay, az)
	local cos_x, sin_x = math.cos(ax), math.sin(ax)
	local y1 = y * cos_x - z * sin_x
	local z1 = y * sin_x + z * cos_x

	local cos_y, sin_y = math.cos(ay), math.sin(ay)
	local x2 = x * cos_y + z1 * sin_y
	local z2 = -x * sin_y + z1 * cos_y

	local cos_z, sin_z = math.cos(az), math.sin(az)
	local x3 = x2 * cos_z - y1 * sin_z
	local y3 = x2 * sin_z + y1 * cos_z

	return x3, y3, z2
end

---Projects a 3D point onto 2D screen space.
---@param x number
---@param y number
---@param z number
---@param fov number Field-of-view multiplier
---@param view_dist number Camera distance
---@param cx number Center X on screen
---@param cy number Center Y on screen
---@return integer px, integer py
function M.project3d(x, y, z, fov, view_dist, cx, cy)
	local factor = fov / (view_dist + z)
	return math.floor(x * factor + cx), math.floor(y * factor + cy)
end

-- ============================================================
--  COMMAND PALETTE
-- ============================================================

---@class dot.ui.palette_opts
---@field title? string Title shown at the top of the palette.
---@field rows string[] Rows to display (first is highlighted).
---@field background? string Background color.
---@field accent? string Accent color for the indicator/title.
---@field on_enter? fun(selected: integer, text: string) Called when Enter is pressed.
---@field on_input? fun(input: string) Called whenever the palette input changes.

---@class dot.ui.Palette
---@field id integer
local Palette = {}
Palette.__index = Palette

---Opens a full-screen command palette that replaces the native command line.
---Keystrokes are routed to this palette until it is closed.
---@param opts dot.ui.palette_opts
---@return dot.ui.Palette
function M.open_palette(opts)
	opts = opts or {}
	local win = M.win.size()
	local palette = setmetatable({
		id = nil,
		opts = opts,
		rows = opts.rows or {},
		rows_max = opts.rows or {},
		selected = 1,
		offset = 0,
		input = "",
		is_open = false,
		completion = nil,
	}, Palette)

	palette:open(win)
	return palette
end

function Palette:_rows_for_width(lines, width)
	local res = {}
	for _, line in ipairs(lines) do
		if #line > width then
			res[#res + 1] = line
		else
			res[#res + 1] = line
		end
	end
	return res
end

function Palette:_build_rows()
	local win = M.win.size()
	local title = self.opts.title or "COMMAND"
	local rows = {}

	table.insert(rows, { text = title .. "  ", fg = self.opts.accent or "#88C0D0", bold = true })
	if #self.input > 0 or (self.completion and self.completion.matches) then
		local suffix = ""
		if self.completion and self.completion.matches then
			suffix = "  [" .. self.completion.index .. "/" .. #self.completion.matches .. "]"
		end
		table.insert(rows, { text = "› " .. self.input .. suffix, fg = "#ECEFF4", bold = true })
	end
	table.insert(rows, { text = "" })

	local avail = math.max(win[1] - #rows - 2, 1)
	local shown = {}
	for i = 1 + self.offset, math.min(1 + self.offset + avail, #self.rows) do
		table.insert(shown, i)
	end

	for _, idx in ipairs(shown) do
		local item
		if idx == self.selected then
			item = {
				text = self.rows[idx],
				fg = "#F8F8F2",
				marker = "▶",
				marker_fg = self.opts.accent or "#88C0D0",
				bold = true,
			}
		else
			item = {
				text = self.rows[idx],
				fg = "#9BA7B8",
				marker_fg = self.opts.accent or "#88C0D0",
			}
		end
		table.insert(rows, item)
	end
	return rows
end

function Palette:open(win)
	local c = win or M.win.size()
	self:filter()
	local cols, rows = c[2], c[1]

	local width = math.min(math.floor(cols * 0.6), 60)
	width = math.max(width, 24)
	local list_rows = self:_build_rows()
	local height = math.min(#list_rows + 2, rows - 2)
	height = math.max(height, 5)

	local pos_x = math.floor((cols - width) / 2) + 1
	local pos_y = math.max(math.floor((rows - height) / 2), 1)

	local popup = M.popup({
		pos = { pos_x, pos_y },
		size = { width, height },
		border = true,
		background = self.opts.background or "#1E232E",
		border_color = self.opts.accent or "#88C0D0",
		indicator = "»",
		rows = list_rows,
	})
	self.is_open = true
	self.id = popup.id
	_dot.palette_activate()
	_dot.palette_on_key = function(key)
		return self:key(key)
	end
	self:refresh()
	return self
end

function Palette:refresh()
	if not self.id then
		return
	end
	_dot.popup_set_screen(self.id, self:_build_rows(), {
		border = true,
		indicator = self.opts.accent or "#88C0D0",
	})
	_dot.needs_redraw = true
end

function Palette:filter()
	local input = self.input:lower()
	if input == "" then
		self.rows = {}
		for _, name in ipairs(_dot.get_native_cmds() or {}) do
			self.rows[#self.rows + 1] = name
		end
		table.sort(self.rows)
		self.selected = 1
		self.offset = 0
		return
	end
	local filtered = {}
	for _, name in ipairs(dot.cmd.list()) do
		if name:lower():sub(1, #input) == input or name:lower():find(input, 1, true) then
			filtered[#filtered + 1] = name
		end
	end
	-- Command + argument form (e.g. `open src/main.c`): no command name can
	-- match, so surface the full input as a runnable row.
	if #filtered == 0 and self.input:match("^%S+%s+%S") then
		filtered[#filtered + 1] = self.input
	end
	self.rows = filtered
	self.selected = 1
	self.offset = 0
end

function Palette:complete(dir)
	local input = self.input
	local cmd, rest = input:match("^(%S+)%s+(.*)$")
	local matches = {}
	local base = ""

	if cmd then
		-- Command with an argument: complete the last token as a path.
		local current_dir = rest:match("^(.*[/\\])") or ""
		local prefix = rest:sub(#current_dir + 1)
		local files = dot.fs.read_dir(current_dir)
		for _, name in ipairs(files or {}) do
			if name:sub(1, #prefix) == prefix then
				matches[#matches + 1] = name
			end
		end
		table.sort(matches)
		base = cmd .. " "
		-- Track the token being completed so repeated Tab cycles within it.
		local token = cmd .. "|" .. current_dir
		if self.completion and self.completion.token == token and
			self.completion.matches then
			local i = (self.completion.index + dir - 1) % #self.completion.matches + 1
			local new_input = base .. current_dir .. self.completion.matches[i]
			_dot.palette_set_input(new_input)
			self.input = _dot.get_palette_input()
			self.completion.index = i
			self:filter()
			self:refresh()
			return
		end
		if #matches == 1 then
			_dot.palette_set_input(base .. current_dir .. matches[1])
			self.input = _dot.get_palette_input()
			self.completion = nil
			self:filter()
			self:refresh()
			return
		end
		self.completion = { matches = matches, index = 1, token = token }
		if #matches > 0 then
			_dot.palette_set_input(base .. current_dir .. matches[1])
			self.input = _dot.get_palette_input()
			self:filter()
			self:refresh()
		end
		return
	end

	-- Command name completion.
	local all = dot.cmd.list()
	for _, name in ipairs(all or {}) do
		if name:sub(1, #input) == input then
			matches[#matches + 1] = name
		end
	end
	if #matches == 1 then
		_dot.palette_set_input(matches[1])
		self.input = _dot.get_palette_input()
		self.completion = nil
		self:filter()
		self:refresh()
		return
	end
	if self.completion and self.completion.token == "cmd|" .. input and
		self.completion.matches then
		local i = (self.completion.index + dir - 1) % #self.completion.matches + 1
		_dot.palette_set_input(self.completion.matches[i])
		self.input = _dot.get_palette_input()
		self.completion.index = i
		self:filter()
		self:refresh()
		return
	end
	if #matches > 1 then
		self.completion = { matches = matches, index = 1, token = "cmd|" .. input }
		_dot.palette_set_input(matches[1])
		self.input = _dot.get_palette_input()
		self:filter()
		self:refresh()
	end
end

function Palette:key(k)
	if k == "escape" then
		self:close()
		_dot.set_cmdline("")
		_dot.set_mode("n")
		return
	end
	if k == "up" then
		self:move(-1)
		return
	end
	if k == "down" then
		self:move(1)
		return
	end
	if k == "tab" then
		self:complete(1)
		return
	end
	if k == "shifttab" then
		self:complete(-1)
		return
	end
	if k == "backspace" then
		self.completion = nil
		_dot.palette_backspace()
		self.input = _dot.get_palette_input()
		self:filter()
		self:refresh()
		return
	end
	if k == "enter" then
		self:enter()
		return
	end
	-- Printable character: forward to palette input.
	self.completion = nil
	_dot.palette_type(k)
	self.input = _dot.get_palette_input()
	if self.opts.on_input then
		self.opts.on_input(self.input)
	end
	self:filter()
	self:refresh()
end

function Palette:move(dir)
	if #self.rows == 0 then
		return
	end
	self.selected = (self.selected - 1 + dir + #self.rows) % #self.rows + 1
	self:refresh()
end

function Palette:enter()
	local chosen = self.rows[self.selected]
	local input = self.input
	close_palette(self)
	if self.opts.on_enter then
		self.opts.on_enter(self.selected, chosen or input)
		return
	end
	if chosen and chosen ~= "" then
		local name, args = chosen:match("^(%S+)%s*(.*)$")
		local handled = dot.cmd.execute(name or chosen, args or "")
		if handled then
			_dot.set_cmdline("")
			_dot.set_mode("n")
		else
			_dot.set_cmdline(chosen)
			_dot.execute_command()
		end
	end
end

function Palette:close()
	close_palette(self)
end

local _active_palette = nil

function close_palette(palette)
	if _active_palette == palette then
		_active_palette = nil
	end
	if palette.id then
		_dot.popup_close(palette.id)
	end
	palette.id = nil
	palette.is_open = false
	_dot.palette_on_key = nil
	_dot.palette_deactivate()
	_dot.needs_redraw = true
end

M.palette = {
	open = function(opts)
		_active_palette = M.open_palette(opts)
		return _active_palette
	end,
	close = close_palette,
	active = function()
		return _active_palette ~= nil
	end,
}

return M