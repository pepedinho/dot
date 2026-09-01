---@class dot.buf
local M = {}

---@class dot.buf.Buffer
---@field id integer
local Buffer = {}
Buffer.__index = Buffer

local function wrap(id)
	return setmetatable({ id = id }, Buffer)
end

---Returns the buffer currently displayed in the active panel.
---@return dot.buf.Buffer
function M.active()
	return wrap(_dot.active_buffer())
end

---Finds a buffer by name (filename or virtual name like "*Messages*").
---@param name string
---@return dot.buf.Buffer|nil
function M.find(name)
	local id = _dot.get_buffer_by_name(name)
	if id then
		return wrap(id)
	end
	return nil
end

---Returns an existing buffer or creates it if missing.
---@param name string
---@return dot.buf.Buffer
function M.open(name)
	local id = _dot.get_buffer_by_name(name)
	if not id then
		id = _dot.create_buffer(name)
	end
	return wrap(id)
end

-- ============================================================
--  Buffer methods
-- ============================================================

---Buffer name (filename or virtual name).
---@return string
function Buffer:name()
	return _dot.buf_name(self.id)
end

---Array of lines `[start_row..end_row]` (inclusive, 1-indexed).
---@param start_row? integer
---@param end_row? integer
---@return string[] lines
function Buffer:lines(start_row, end_row)
	return _dot.buf_lines(self.id, start_row or 1, end_row or 99999999)
end

---Replaces `[start_row..end_row]` with `lines`. Identical start/end inserts.
---@param start_row integer
---@param end_row integer
---@param lines string[]
---@return dot.buf.Buffer self
function Buffer:set_lines(start_row, end_row, lines)
	_dot.set_buffer_lines(self.id, start_row, end_row, lines)
	return self
end

---Appends `text` plus a newline at the end of the buffer.
---@param text string
---@return dot.buf.Buffer self
function Buffer:append(text)
	_dot.append_to_buffer(self.id, text)
	return self
end

---Empties the buffer.
---@return dot.buf.Buffer self
function Buffer:clear()
	_dot.clear_buffer(self.id)
	return self
end

---Cursor getter/setter. `buf:cursor()` returns `{ row, col }`.
---`buf:cursor(row, [col])` moves the cursor.
---@param row? integer
---@param col? integer
---@return integer[]|dot.buf.Buffer
function Buffer:cursor(...)
	local n = select("#", ...)
	if n == 0 then
		return _dot.buf_cursor(self.id)
	end
	local row, col = ...
	_dot.set_buffer_cursor(self.id, row, col or 1)
	return self
end

---@class dot.buf.highlight_opts
---@field ns? integer Namespace id (default 0)
---@field row integer
---@field col integer
---@field len integer
---@field style? table
---@field priority? integer

---Colors a range of this buffer. Accepts an options table or
---`(ns, row, col, len, style, priority)`.
---@param ... dot.buf.highlight_opts | integer
---@return dot.buf.Buffer self
function Buffer:highlight(...)
	local args = { ... }
	local ns, row, col, len, st, prio
	if type(args[1]) == "table" then
		local o = args[1]
		ns, row, col, len, st, prio = o.ns or 0, o.row or 1, o.col or 1, o.len or 0, o.style or {}, o.priority or 50
	else
		ns, row, col, len, st, prio = args[1] or 0, args[2] or 1, args[3] or 1, args[4] or 0, args[5] or {}, args[6] or 50
	end
	_dot.add_buffer_style(self.id, ns, row, col, len, st, prio)
	return self
end

---Removes all highlights of a namespace from this buffer.
---@param ns integer
---@return dot.buf.Buffer self
function Buffer:clear_highlight(ns)
	_dot.clear_buffer_style(self.id, ns or 0)
	return self
end

---Displays this buffer in the active panel (read-only view).
---@return dot.buf.Buffer self
function Buffer:show()
	_dot.set_view_buffer(self.id)
	return self
end

---`true` when the panel currently showing this buffer is read-only.
---@return boolean
function Buffer:is_readonly()
	local info = _dot.get_debug_info()
	for _, v in ipairs(info.views or {}) do
		if v and v.buf_idx == self.id then
			return v.is_readonly == true
		end
	end
	return false
end

---Writes this buffer to its associated file.
---@return dot.buf.Buffer self
function Buffer:save()
	_dot.buf_save(self.id)
	return self
end

return M