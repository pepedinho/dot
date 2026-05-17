local M = {}

local registry = {
	zig = {
		repo = "https://github.com/maxxnino/tree-sitter-zig",
		files = "src/parser.c",
	},
	c = {
		repo = "https://github.com/tree-sitter/tree-sitter-c",
		files = "src/parser.c",
	},
	lua = {
		repo = "https://github.com/MunifTanjim/tree-sitter-lua",
		files = "src/parser.c src/scanner.c",
	},
}

local function ts_install(lang)
	if not lang or lang == "" then
		dot.print("usage: lang-install <lang>")
		return
	end

	local info = registry[lang]
	if not info then
		dot.print("lang unsupported: " .. lang)
		return
	end

	dot.print("⏳ Installing Tree-sitter for " .. lang .. " in background...")

	local home = os.getenv("HOME")
	local parsers_dir = home .. "/.config/dot/parsers"
	local queries_dir = home .. "/.config/dot/queries/" .. lang
	local tmp_dir = "/tmp/dot_ts_" .. lang
	local sh_filepath = "/tmp/dot_install_" .. lang .. ".sh"

	local script = string.format(
		[[
#!/bin/sh
mkdir -p %s
mkdir -p %s
rm -rf %s
git clone --depth 1 --quiet %s %s
cd %s
zig cc -fPIC -shared -O3 %s -I src -o %s/%s.so
if [ -f queries/highlights.scm ]; then
    cp queries/highlights.scm %s/
fi
rm -rf %s
]],
		parsers_dir,
		queries_dir,
		tmp_dir,
		info.repo,
		tmp_dir,
		tmp_dir,
		info.files,
		parsers_dir,
		lang,
		queries_dir,
		tmp_dir
	)

	local f = io.open(sh_filepath, "w")
	if f then
		f:write(script)
		f:close()
	else
		dot.print("❌ Failed to create install script")
		return
	end

	dot.spawn("sh " .. sh_filepath, function(success, output)
		if success then
			dot.print("✅ " .. lang .. " installed successfully !")
		else
			dot.print("❌ Failed to install " .. lang)
			if output and output ~= "" then
				-- Optionnel: log l'erreur de zig cc si ça plante
				dot.print("Error: " .. string.sub(output, 1, 100) .. "...")
			end
		end

		os.remove(sh_filepath)
	end)
end

local cmd = require("dot.core.commands")
cmd.create("lang-install", ts_install)

return M
