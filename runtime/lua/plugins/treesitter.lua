local M = {}

local ext_to_lang = {
	zig = "zig",
	lua = "lua",
	c = "c",
	h = "c",
	rs = "rust",
	py = "python",
	js = "javascript",
	ts = "typescript",
}

local home = os.getenv("HOME")
local parsers_dir = home .. "/.config/dot/parsers/"
local queries_dir = home .. "/.config/dot/queries/"

local current_loaded_lang = nil

local function update_tree()
	local filename = dot.get_file()
	if not filename or filename == "" then
		return false
	end

	local ext = filename:match("^.+(%..+)$")
	if not ext then
		return false
	end
	ext = ext:sub(2)

	local lang_name = ext_to_lang[ext]
	if not lang_name then
		return false
	end

	if current_loaded_lang == lang_name then
		return false
	end

	local lib_path = parsers_dir .. lang_name .. ".so"
	local query_path = queries_dir .. lang_name .. "/highlights.scm"

	local f = io.open(lib_path, "r")
	if f then
		f:close()
		dot.print("🌳 Tree-sitter loaded : " .. lang_name)
		dot.ts_load_language(lang_name, lib_path, query_path)
		current_loaded_lang = lang_name
	else
		dot.print("lang not found: use lang-install <lang>")
	end

	return false
end

dot.hook_on("BufInit", update_tree)
dot.hook_on("BufOpen", update_tree)
local cmd = require("dot.commands")
cmd.create("ts", update_tree)

return M
