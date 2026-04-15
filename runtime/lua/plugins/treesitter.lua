local M = {}

local languages = {
	zig = {
		name = "zig",
		lib = os.getenv("PWD") .. "/parsers/zig.so",
		query = os.getenv("HOME") .. "/.config/dot/queries/zig/highlights.scm",
	},
}

local function update_tree()
	local filename = dot.get_file()
	if not filename or filename == "" then
		return false
	end

	local ext = filename:match("^.+(%..+)$")
	if ext then
		ext = ext:sub(2)
		local lang = languages[ext]

		if lang then
			dot.ts_load_language(lang.name, lang.lib, lang.query)
		end
	end
	return false
end

dot.hook_on("SpaceInsert", update_tree)
dot.hook_on("BufInit", update_tree)
dot.hook_on("ModeChanged", update_tree)
dot.hook_on("BackSpace", update_tree)

return M
