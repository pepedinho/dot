local json = require("json")
local zls_id = nil
local stdout_buffer = ""
local file_version = 1
local error_fg = "#F14C4C"
local error_bg = "#421B1B"
local LSP_NAMESPACE = 3
local LSP_PRIORITY = 100

local function make_request(id, method, params_json_str)
	local payload = string.format('{"jsonrpc":"2.0","id":%d,"method":"%s","params":%s}', id, method, params_json_str)
	return string.format("Content-Length: %d\r\n\r\n%s", #payload, payload)
end

local function make_notification(method, params_table)
	local payload_table = { jsonrpc = "2.0", method = method }
	if params_table then
		payload_table.params = params_table
	end
	local payload = json.encode(payload_table)
	return string.format("Content-Length: %d\r\n\r\n%s", #payload, payload)
end

local pwd = os.getenv("PWD")
local filename = dot.get_file()
local filepath = filename
if string.sub(filename, 1, 1) ~= "/" then
	filepath = pwd .. "/" .. filename
end
local real_uri = "file://" .. filepath

local function sync_buffer_to_lsp()
	if not zls_id then
		return
	end
	file_version = file_version + 1
	local lines = dot.get_lines(1, 99999)
	local full_text = table.concat(lines, "\n") .. "\n"

	local change_msg = make_notification("textDocument/didChange", {
		textDocument = {
			uri = real_uri,
			version = file_version,
		},
		contentChanges = { { text = full_text } },
	})
	dot.server_send(zls_id, change_msg)
	dot.print("🔄 Sync sent to ZLS...")
end

dot.hook_on("ModeChanged", function()
	local current_mode = dot.get_mode()
	if current_mode == "Normal" then
		sync_buffer_to_lsp()
	end
end)

local function handle_lsp_message(data)
	if data.method then
		dot.print("📡 ZLS a send : " .. data.method)
	end

	-- if data.method == "window/logMessage" then
	-- 	dot.print("ZLS Log: " .. data.params.message)
	-- end

	if data.id == 1 then
		dot.print("✅ ZLS Init! Send file ...")

		local init_notif = '{"jsonrpc":"2.0","method":"initialized","params":{}}'
		local init_payload = string.format("Content-Length: %d\r\n\r\n%s", #init_notif, init_notif)
		dot.server_send(zls_id, init_payload)

		local lines = dot.get_lines(1, 99999)
		local text = table.concat(lines, "\n") .. "\n"
		local did_open_msg = make_notification("textDocument/didOpen", {
			textDocument = {
				uri = real_uri,
				languageId = "zig",
				version = 1,
				text = text,
			},
		})
		dot.server_send(zls_id, did_open_msg)
	elseif data.method == "textDocument/publishDiagnostics" then
		dot.clear_style(LSP_NAMESPACE)
		dot.clear_ghosts()
		local diags = data.params.diagnostics
		if #diags > 0 then
			dot.print("⚠️ ZLS Found " .. #diags .. " error(s) !")
			for _, diag in ipairs(diags) do
				local row = diag.range.start.line + 1
				local col = diag.range.start.character + 1
				local length = diag.range["end"].character - diag.range.start.character
				if length <= 0 then
					length = 1
				end

				dot.add_style(LSP_NAMESPACE, row, col, length, { fg = error_fg, underline = true }, LSP_PRIORITY)
				dot.add_ghost(row, col, diag.message, "└── ", { fg = error_fg, bg = error_bg, italic = true })
			end
		else
			dot.print("✅ No error !")
		end
	end
end

dot.print("🔌 Run ZLS in background...")

local home_dir = os.getenv("HOME")
local zls_path = home_dir .. "/.local/share/nvim/mason/bin/zls"

zls_id = dot.start_server(zls_path, function(success, chunk)
	if not success or not chunk then
		return
	end
	stdout_buffer = stdout_buffer .. chunk

	while true do
		local header_start, header_end = string.find(stdout_buffer, "\r\n\r\n")
		if not header_start then
			break
		end

		local headers = string.sub(stdout_buffer, 1, header_start - 1)
		local _, _, length_str = string.find(headers, "Content%-Length: (%d+)")

		if not length_str then
			stdout_buffer = string.sub(stdout_buffer, header_end + 1)
			break
		end

		local content_length = tonumber(length_str)
		local total_msg_len = header_end + content_length

		if #stdout_buffer >= total_msg_len then
			local json_payload = string.sub(stdout_buffer, header_end + 1, total_msg_len)
			stdout_buffer = string.sub(stdout_buffer, total_msg_len + 1)

			local ok, parsed_data = pcall(json.decode, json_payload)
			if ok and parsed_data then
				handle_lsp_message(parsed_data)
			else
				dot.print("ERROR: Failed to parse ZLS response")
			end
		else
			break
		end
	end
end)

if zls_id and zls_id > 0 then
	dot.print("zls id : " .. zls_id)
	local root_uri = "file://" .. pwd
	local caps = '{"textDocument":{"publishDiagnostics":{"relatedInformation":true}}}'

	local init_params_str = string.format('{"processId":null,"rootUri":"%s","capabilities":%s}', root_uri, caps)
	local init_msg = make_request(1, "initialize", init_params_str)
	dot.server_send(zls_id, init_msg)
end
