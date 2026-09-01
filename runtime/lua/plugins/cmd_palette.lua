local M = {}

local State = { open = false, popup = nil, matches = {}, selected = 1, offset = 1 }
local MAX_ROWS = 10

local function render()
	local lines = {}
	for i = State.offset, math.min(State.offset + MAX_ROWS, #State.matches) do
		local mark = (i == State.selected) and " " or "  "
		lines[#lines + 1] = mark .. State.matches[i]
	end
	if State.popup then
		State.popup:set_text(table.concat(lines, "\n"))
	end
end

local function open()
	local input = dot.cmd.input():match("^%s*(%S*)") or ""
	State.matches, State.selected, State.offset = {}, 1, 1
	for _, name in ipairs(dot.cmd.list()) do
		if name:sub(1, #input) == input then
			State.matches[#State.matches + 1] = name
		end
	end

	if #State.matches == 0 then
		return
	end

	local win = dot.ui.win.size()
	local w, h = 26, math.min(#State.matches, MAX_ROWS) + 2
	State.popup = dot.ui.popup({
		size = { w, h },
		pos = { math.floor((win[2] - w) / 2) + 1, math.floor((win[1] - h) / 2) + 1 },
	})
	State.open = true
	render()
end

local function close()
	if State.popup then
		State.popup:close()
	end
	State.popup, State.open = nil, false
end

local function move(dir)
	if not State.open then
		return false
	end
	State.selected = (State.selected - 1 + dir + #State.matches) % #State.matches + 1
	if State.selected < State.offset then
		State.offset = State.selected
	end
	if State.selected >= State.offset + MAX_ROWS then
		State.offset = State.selected - MAX_ROWS + 1
	end
	render()
	return true
end

dot.hook.on("CmdTab", function()
	if State.open then
		return move(1)
	end
	open()
	return true
end)

dot.hook.on("CmdSTab", function()
	return move(-1)
end)

dot.hook.on("Up", function()
	return State.open and move(1) or false
end)
dot.hook.on("Down", function()
	return State.open and move(-1) or false
end)

dot.hook.on("CmdEnter", function()
	if not State.open then
		return false
	end
	local chosen = State.matches[State.selected]
	close()
	if not chosen then
		return false
	end
	local name, args = chosen:match("^(%S+)%s*(.*)$")
	dot.cmd.set_input(chosen)
	-- registre => déjà exécuté (return true bloque ExecuteCommand) ;
	-- natif => on laisse l'ExecuteCommand sur la ligne remplie.
	return dot.cmd.execute(name or chosen, args or "")
end)

dot.hook.on("CmdEsc", function()
	if State.open then
		close()
		return true
	end -- reste en mode commande
	return false
end)
