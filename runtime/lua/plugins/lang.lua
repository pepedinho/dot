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
		dot.print("lang unsuported: " .. lang)
		return
	end

	dot.print("Installing Tree-sitter for " .. lang .. "...")

	local home = os.getenv("HOME")
	local parsers_dir = home .. "/.config/dot/parsers"
	local queries_dir = home .. "/.config/dot/queries/" .. lang
	local tmp_dir = "/tmp/dot_ts_" .. lang

	local script = string.format(
		[[
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

	local success = os.execute(script)

	if success then
		dot.print(lang .. " installed successfully !")
	else
		dot.print("failed to install " .. lang)
	end
end

local cmd = require("dot.commands")
cmd.create("lang-install", ts_install)

return M
