---@meta dot
-- This file assembles the public `dot.*` API from the `_dot` primitives.
-- It is loaded automatically by the editor on startup (`startLua`).

local ui = require("dot.ui")
local buf = require("dot.buf")
local edit = require("dot.edit")
local cmd = require("dot.cmd")
local mode = require("dot.mode")
local keymap = require("dot.keymap")
local hook = require("dot.hook")
local fs = require("dot.fs")
local sys = require("dot.sys")
local ts = require("dot.ts")
local timer = require("dot.timer")
local style = require("dot.style")
local log = require("dot.log")
local debug = require("dot.debug")

_G.dot = {
	ui = ui,
	buf = buf,
	edit = edit,
	cmd = cmd,
	mode = mode,
	keymap = keymap,
	hook = hook,
	fs = fs,
	sys = sys,
	ts = ts,
	timer = timer,
	style = style,
	log = log,
	debug = debug,
}

return _G.dot