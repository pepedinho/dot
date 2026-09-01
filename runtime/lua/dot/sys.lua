---@class dot.sys
local M = {}

---Runs a command in the background without blocking the editor.
---@param cmd string Shell command (e.g. "grep -rn TODO src").
---@param callback fun(success: boolean, output: string|nil)
function M.spawn(cmd, callback)
	if type(cmd) ~= "string" or type(callback) ~= "function" then
		error("dot.sys.spawn(cmd, callback): invalid arguments")
	end
	_dot.spawn(cmd, callback)
end

---@class dot.sys.server
local server = {}

---Starts a long-running background process (e.g. an LSP server).
---@param cmd string Command to run (e.g. "zls").
---@param on_message fun(alive: boolean, chunk: string|nil) Called on each stdout chunk.
---@return integer id Server id used by send/stop.
function server.start(cmd, on_message)
	if type(cmd) ~= "string" or type(on_message) ~= "function" then
		error("dot.sys.server.start(cmd, on_message): invalid arguments")
	end
	return _dot.start_server(cmd, on_message)
end

---Writes a payload to the process stdin (framing is your responsibility,
---e.g. "Content-Length: N\r\n\r\n").
---@param id integer
---@param message string
function server.send(id, message)
	_dot.server_send(id, message)
end

---Kills the process.
---@param id integer
function server.stop(id)
	_dot.server_stop(id)
end

M.server = server

---@class dot.sys.opts
---@field name? string

---Saves the active buffer to its file.
function M.save()
	_dot.save_current_file()
end

return M