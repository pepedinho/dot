---@class dot.ts
local M = {}

---Loads a Tree-sitter language grammar for the active buffer.
---@param name string Language name (e.g. "c").
---@param lib_path string Path to the parser .so file.
---@param query_path string Path to the highlights.scm query file.
function M.load(name, lib_path, query_path)
	_dot.ts_load_language(name, lib_path, query_path)
end

---Returns the S-expression of the current AST, or nil if none.
---@return string|nil ast
function M.parse()
	return _dot.ts_parse()
end

return M