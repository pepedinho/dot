---@class dot.fs
local M = {}

---Lists the entries of a directory. Directories carry a trailing "/".
---@param path? string Directory path (default: current directory).
---@return string[] entries
function M.read_dir(path)
	return _dot.read_dir(path or "")
end

return M