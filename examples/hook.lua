dot.print("Plugin Auto-Cleaner Loaded!")

dot.hook_on("BufWritePre", function()
	local cursor = dot.get_cursor()
	local row = cursor[1]

	dot.insert("\n// File Saved by Plugin")
	dot.print("Hook BufWritePre triggered")
	return true
end)

