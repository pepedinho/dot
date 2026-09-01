dot.ui.notify("Plugin Auto-Cleaner Loaded!")

dot.hook.on("BufWritePre", function()
	local cursor = dot.ui.cursor.get()
	local row = cursor[1]

	dot.edit.insert("\n// File Saved by Plugin")
	dot.ui.notify("Hook BufWritePre triggered")
	return true
end)