---@class dot.debug
local M = {}

---@class dot.debug.Buffer
---@field filename string
---@field len integer
---@field logical_size integer
---@field gap_start integer
---@field gap_end integer

---@class dot.debug.View
---@field buf_idx integer
---@field x integer
---@field y integer
---@field width integer
---@field height integer
---@field is_active boolean
---@field is_readonly boolean

---@class dot.debug.Info
---@field fps integer
---@field timestamp integer
---@field mem_kb integer
---@field queue_size integer
---@field buffers dot.debug.Buffer[]
---@field views dot.debug.View[]
---@field actions string[]

---Returns comprehensive introspection of the editor state.
---@return dot.debug.Info
function M.info()
	return _dot.get_debug_info()
end

return M