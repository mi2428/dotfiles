local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
local mini_map_root = vim.fs.joinpath(vim.fn.stdpath("data"), "lazy/mini.map")
vim.opt.runtimepath:prepend(nvim_root)
vim.opt.runtimepath:prepend(mini_map_root)
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	vim.fs.joinpath(mini_map_root, "lua/?.lua"),
	package.path,
}, ";")

local function upvalue(fn, expected_name)
	for index = 1, math.huge do
		local name, value = debug.getupvalue(fn, index)
		if not name then
			break
		end
		if name == expected_name then
			return value
		end
	end
	error("missing upvalue: " .. expected_name)
end

local function wait_for(predicate, message)
	assert(vim.wait(2000, predicate, 10), message)
end

local function local_sidescrolloff(win)
	return vim.api.nvim_get_option_value("sidescrolloff", { scope = "local", win = win })
end

local specs = dofile(vim.fs.joinpath(nvim_root, "lua/plugins/minimap.lua"))
local setup_code_layout = upvalue(specs[1].config, "setup_code_layout")
local map = require("mini.map")

vim.o.columns = 120
vim.o.lines = 40
vim.o.laststatus = 0
vim.o.showtabline = 0
vim.o.sidescroll = 1
vim.o.sidescrolloff = 4
vim.wo.number = false
vim.wo.relativenumber = false
vim.wo.signcolumn = "no"
vim.wo.statuscolumn = ""
vim.wo.wrap = false
local long_line = ("0123456789"):rep(30)
vim.api.nvim_buf_set_lines(0, 0, -1, false, { long_line, "short" })

map.setup({
	integrations = {},
	symbols = { encode = map.gen_encode_symbols.dot("4x2") },
	window = { focusable = false, show_integration_count = false, width = 12, winblend = 0, zindex = 30 },
})
setup_code_layout(map)
map.open()

local manager = map._dotfiles_multi_window_manager
local function map_width(source_win)
	local map_win = manager.map_window_for_source(source_win)
	return map_win and vim.api.nvim_win_is_valid(map_win) and vim.api.nvim_win_get_width(map_win) or nil
end

local function assert_reserved(source_win, base, restore_local, message)
	wait_for(function()
		local width = map_width(source_win)
		local state = manager.source_margins[source_win]
		return width
			and state
			and state.restore_local == restore_local
			and local_sidescrolloff(source_win) == base + width
	end, message)
end

local function assert_cursor_stays_left_of_map(source_win, base, message)
	vim.api.nvim_win_call(source_win, function()
		vim.wo.wrap = false
		vim.api.nvim_win_set_cursor(source_win, { 1, 0 })
		for column = 1, #long_line - 1 do
			vim.api.nvim_win_set_cursor(source_win, { 1, column })
			vim.cmd.redraw()
		end
	end)
	local width = assert(map_width(source_win))
	local view = vim.api.nvim_win_call(source_win, vim.fn.winsaveview)
	local cursor_column = vim.api.nvim_win_call(source_win, function()
		return vim.fn.virtcol(".") - view.leftcol
	end)
	local map_left = vim.api.nvim_win_get_width(source_win) - width + 1
	assert(cursor_column < map_left, message .. ": cursor entered the minimap interval")
	assert(map_left - cursor_column - 1 >= base, message .. ": original horizontal context was lost")
end

local first = vim.api.nvim_get_current_win()
assert(local_sidescrolloff(first) == -1, "fixture must initially inherit global sidescrolloff")
assert_reserved(first, 4, -1, "initial source did not reserve the minimap width")
assert_cursor_stays_left_of_map(first, 4, "initial source")

vim.cmd.vsplit()
local second = vim.api.nvim_get_current_win()
assert_reserved(first, 4, -1, "vertical split changed the first source margin")
assert_reserved(second, 4, -1, "vertical split double-counted the inherited reserved margin")
assert_cursor_stays_left_of_map(second, 4, "vertical split")

vim.api.nvim_win_call(second, function()
	vim.cmd("setlocal sidescrolloff=7")
end)
assert_reserved(second, 7, 7, "a user-local sidescrolloff change was not adopted as the new base")

vim.cmd("setglobal sidescrolloff=6")
assert_reserved(first, 6, -1, "an inherited global sidescrolloff change did not update the reservation")
assert_reserved(second, 7, 7, "a global change overwrote a local sidescrolloff base")

vim.api.nvim_set_current_win(second)
vim.cmd.split()
local third = vim.api.nvim_get_current_win()
assert_reserved(third, 7, 7, "a horizontal split treated its copied reservation as a new base")

vim.w[third].dotfiles_disable_minimap = true
map.refresh({}, { layout = true, integrations = false, lines = false, scrollbar = false })
wait_for(function()
	return manager.source_margins[third] == nil and local_sidescrolloff(third) == 7
end, "a minimap opt-out did not restore the source margin")
vim.w[third].dotfiles_disable_minimap = false
map.refresh({}, { layout = true, integrations = false, lines = false, scrollbar = false })
assert_reserved(third, 7, 7, "re-enabling a minimap did not restore its reservation")

map.refresh({ window = { width = 8 } }, { integrations = false, lines = false, scrollbar = false })
wait_for(function()
	return map_width(first) == 8 and map_width(second) == 8
end, "fixture minimap widths did not shrink")
assert_reserved(first, 6, -1, "a minimap width reduction left a stale inherited margin")
assert_reserved(second, 7, 7, "a minimap width reduction left a stale local margin")
map.refresh({ window = { width = 12 } }, { integrations = false, lines = false, scrollbar = false })
wait_for(function()
	return map_width(first) == 12 and map_width(second) == 12
end, "fixture minimap widths did not return to configured width")
assert_reserved(first, 6, -1, "restoring minimap width left a stale inherited margin")
assert_reserved(second, 7, 7, "restoring minimap width left a stale local margin")

vim.api.nvim_set_current_win(first)
vim.cmd("leftabove 8vnew")
local narrow = vim.api.nvim_get_current_win()
vim.wo[narrow].wrap = false
vim.api.nvim_buf_set_lines(0, 0, -1, false, { long_line })
wait_for(function()
	return map_width(narrow) == vim.api.nvim_win_get_width(narrow)
		and manager.source_margins[narrow] == nil
		and local_sidescrolloff(narrow) == -1
end, "a map wider than half its pane retained an ineffective reservation")
vim.api.nvim_win_call(narrow, function()
	vim.cmd("vertical resize 40")
end)
vim.api.nvim_exec_autocmds("WinResized", { group = "dotfiles-mini-map-code-layout", modeline = false })
local resized = vim.wait(2000, function()
	return map_width(narrow) == 12
end, 10)
assert(
	resized,
	("resized narrow minimap did not return to configured width (source=%s map=%s)"):format(
		vim.api.nvim_win_get_width(narrow),
		tostring(map_width(narrow))
	)
)
assert_reserved(narrow, 6, -1, "resizing a narrow split did not update its reservation")
assert_cursor_stays_left_of_map(narrow, 6, "resized narrow split")

local tracked = {
	[first] = -1,
	[second] = 7,
	[third] = 7,
	[narrow] = -1,
}
map.close()
wait_for(function()
	return next(manager.source_margins) == nil and next(manager.mirrors) == nil
end, "closing minimap did not release source margin state")
for win, expected in pairs(tracked) do
	assert(vim.api.nvim_win_is_valid(win), "fixture source window closed unexpectedly")
	assert(local_sidescrolloff(win) == expected, "closing minimap did not restore the exact local option state")
end
assert(vim.wo[first].sidescrolloff == 6, "restored inherited margin did not follow the new global value")

vim.api.nvim_set_current_win(first)
map.open()
assert_reserved(first, 6, -1, "reopening minimap did not reserve inherited margin")
assert_reserved(second, 7, 7, "reopening minimap did not reserve local margin")
vim.api.nvim_win_close(third, true)
wait_for(function()
	return manager.source_margins[third] == nil
end, "closing a source split leaked margin state")
map.close()

print("minimap nowrap margin regression: ok")
