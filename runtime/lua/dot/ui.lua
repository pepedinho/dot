---@meta dot.ui
local M = {}

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

-- ==============================================================================
--  3D MATH ENGINE
-- ==============================================================================

--- Rotates a 3D point around the X, Y, and Z axes using rotation matrices.
---@param x number The X coordinate.
---@param y number The Y coordinate.
---@param z number The Z coordinate.
---@param ax number The rotation angle around the X axis (in radians).
---@param ay number The rotation angle around the Y axis (in radians).
---@param az number The rotation angle around the Z axis (in radians).
---@return number x, number y, number z The new rotated coordinates.
function M.rotate_3d(x, y, z, ax, ay, az)
	-- X-axis rotation
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

--- Projects a 3D coordinate onto a 2D screen space.
---@param x number The 3D X coordinate.
---@param y number The 3D Y coordinate.
---@param z number The 3D Z coordinate.
---@param fov number The Field of View multiplier.
---@param view_dist number The distance of the camera from the object.
---@param cx number The center X position on the 2D screen.
---@param cy number The center Y position on the 2D screen.
---@return integer px, integer py The 2D projected coordinates.
function M.project_3d(x, y, z, fov, view_dist, cx, cy)
	local factor = fov / (view_dist + z)
	local px = math.floor(x * factor + cx)
	local py = math.floor(y * factor + cy)
	return px, py
end

-- ==============================================================================
--  BRAILLE SUB-PIXEL CANVAS
-- ==============================================================================

local SUB_IDX_MAP = {
	{ 0x01, 0x08 },
	{ 0x02, 0x10 },
	{ 0x04, 0x20 },
	{ 0x40, 0x80 },
}

local BrailleCanvas = {}
BrailleCanvas.__index = BrailleCanvas

--- Creates a new Braille canvas for sub-pixel rendering.
---@param width integer Width in terminal columns (gives width * 2 sub-pixels).
---@param height integer Height in terminal rows (gives height * 4 sub-pixels).
---@return table
function M.new_braille_canvas(width, height)
	local self = setmetatable({}, BrailleCanvas)
	self.width = width
	self.height = height
	self.dots = {}
	for i = 1, width * height do
		self.dots[i] = 0
	end
	return self
end

--- Sets a single sub-pixel on the canvas.
---@param px integer Sub-pixel X coordinate.
---@param py integer Sub-pixel Y coordinate.
function BrailleCanvas:set_pixel(px, py)
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

--- Draws a straight line between two points using Bresenham's line algorithm.
---@param x0 integer Starting sub-pixel X.
---@param y0 integer Starting sub-pixel Y.
---@param x1 integer Ending sub-pixel X.
---@param y1 integer Ending sub-pixel Y.
function BrailleCanvas:draw_line(x0, y0, x1, y1)
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

--- Plots a smoothed curve from an array of historical data.
---@param data number[] Array of numerical values.
function BrailleCanvas:plot_smooth_curve(data)
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

--- Converts the binary sub-pixel canvas into an array of UTF-8 strings.
---@return string[] lines The rendered Braille characters.
function BrailleCanvas:to_utf8_lines()
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

function M.create_gauge(val, max, width)
	local fill_char = "█"
	local empty_char = "░"
	local ratio = math.min(math.max(val / max, 0), 1)
	local filled = math.floor(ratio * width)
	local empty = width - filled
	return string.rep(fill_char, filled) .. string.rep(empty_char, empty)
end

return M
