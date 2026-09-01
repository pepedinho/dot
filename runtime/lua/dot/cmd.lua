---@class dot.cmd
local M = {}

local registry = {}

---List of previously entered command lines.
---@type string[]
M.history = {}

---Registers a user command.
---@param name string Command name (e.g. "format").
---@param callback fun(args: string) Called with the argument string ("" if none).
function M.create(name, callback)
	if type(name) ~= "string" or type(callback) ~= "function" then
		error("dot.cmd.create(name, callback): invalid arguments")
	end
	registry[name] = callback
end

---All command names (built-in + user), sorted.
---@return string[] commands
function M.list()
	local list = {}
	local native = _dot.get_native_cmds()
	if native then
		for _, name in ipairs(native) do
			table.insert(list, name)
		end
	end
	for name in pairs(registry) do
		table.insert(list, name)
	end
	table.sort(list)
	return list
end

---Current command-line text.
---@return string
function M.input()
	return _dot.get_cmdline()
end

---Replaces the command-line text.
---@param text string
function M.set_input(text)
	_dot.set_cmdline(tostring(text))
end

---Executes a registered Lua command by name. Returns `true` if the command was
---found and run, `false` otherwise (so native commands can fall through).
---@param name string
---@param args? string
---@return boolean handled
function M.execute(name, args)
	if type(name) ~= "string" then
		return false
	end
	local cb = registry[name]
	if not cb then
		return false
	end
	local ok, err = pcall(cb, args or "")
	if not ok then
		_dot.print("dot.cmd: " .. name .. ": " .. tostring(err), { fg = "#FFFFFF", bg = "#BF616A" })
	end
	return true
end

-- Dispatch: built-in commands fall through to the native commands, `registry`
-- commands are executed as Lua callbacks.
_dot.hook_on("CmdEnter", function()
	local cmd_line = _dot.get_cmdline()
	local cmd_name, args = cmd_line:match("^%s*(%S+)%s*(.*)$")

	if cmd_line and cmd_line ~= "" then
		table.insert(M.history, cmd_line)
	end

	if not cmd_name then
		return false
	end

	if registry[cmd_name] then
		M.execute(cmd_name, args or "")
		_dot.set_cmdline("")
		_dot.set_mode("n")
		return true
	end
	return false
end)

return M