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

vim.o.columns = 80
vim.o.lines = 24
vim.o.laststatus = 0
vim.o.showtabline = 0

local specs = dofile(vim.fs.joinpath(nvim_root, "lua/plugins/minimap.lua"))
local setup_code_layout = upvalue(specs[1].config, "setup_code_layout")
local set_minimap_highlights = upvalue(specs[1].config, "set_minimap_highlights")
local map = require("mini.map")

local source_win = vim.api.nvim_get_current_win()
local source_lines = {}
for _ = 1, 40 do
	source_lines[#source_lines + 1] = string.rep("x", 100)
end
vim.api.nvim_buf_set_lines(0, 0, -1, false, source_lines)
map.setup({
	integrations = {},
	symbols = { encode = map.gen_encode_symbols.dot("4x2") },
	window = { focusable = false, show_integration_count = false, width = 12, winblend = 0, zindex = 30 },
})
set_minimap_highlights()
setup_code_layout(map)
map.open()

local manager = map._dotfiles_multi_window_manager
local map_win = map.current.win_data[vim.api.nvim_get_current_tabpage()]
wait_for(function()
	return map_win and vim.api.nvim_win_is_valid(map_win) and manager.rendered_maps[map_win]
end, "minimap display renderer did not initialize")

map.refresh({ window = { width = 8 } }, { lines = false, integrations = false, scrollbar = false })
wait_for(function()
	local display = manager.rendered_maps[map_win]
	return vim.api.nvim_win_get_width(map_win) == 8
		and display
		and vim.api.nvim_win_is_valid(display.win)
		and vim.api.nvim_win_get_width(display.win) == 8
end, "a no-lines width update left stale display geometry")
map.refresh({ window = { width = 12 } }, { lines = false, integrations = false, scrollbar = false })
wait_for(function()
	local display = manager.rendered_maps[map_win]
	return vim.api.nvim_win_get_width(map_win) == 12
		and display
		and vim.api.nvim_win_is_valid(display.win)
		and vim.api.nvim_win_get_width(display.win) == 12
end, "restoring width left stale display geometry")

local map_buf = vim.api.nvim_win_get_buf(map_win)
vim.api.nvim_buf_clear_namespace(map_buf, -1, 0, -1)
vim.api.nvim_buf_set_lines(map_buf, 0, -1, false, {
	"┃⠁⠀ ⠂", -- glyphs and holes still reserve the complete minimap width
	"⠀⠀", -- an empty encoded row is still inside the vertical minimap span
	"界⠀",
	"",
})
local virtual_namespace = vim.api.nvim_create_namespace("dotfiles-minimap-opaque-interval-test")
vim.api.nvim_buf_set_extmark(map_buf, virtual_namespace, 3, 0, {
	virt_text = { { "X", "MiniMapSymbolLine" } },
	virt_text_win_col = 8,
})
manager.schedule({ lines = true, integrations = false, scrollbar = false })

wait_for(function()
	local display = manager.rendered_maps[map_win]
	return display
		and vim.api.nvim_win_is_valid(display.win)
		and vim.api.nvim_win_get_buf(display.win) == map_buf
		and vim.api.nvim_win_get_width(display.win) == vim.api.nvim_win_get_width(map_win)
		and vim.api.nvim_win_get_height(display.win) == 4
end, "encoded minimap span did not create one full-width display")

local normal = vim.api.nvim_get_hl(0, { name = "MiniMapNormal", link = false })
assert(normal.bg ~= nil and (not normal.blend or normal.blend == 0), "occupied interval background must be opaque")
local display = assert(manager.rendered_maps[map_win], "minimap has no display float")
local source_position = vim.api.nvim_win_get_position(source_win)
local expected_left = source_position[2] + vim.api.nvim_win_get_width(source_win) - vim.api.nvim_win_get_width(map_win)
local display_config = vim.api.nvim_win_get_config(display.win)
assert(display_config.row == source_position[1], "display float is vertically misplaced")
assert(display_config.col == expected_left, "display float is horizontally misplaced")
assert(display_config.width == vim.api.nvim_win_get_width(map_win), "display must cover from rail to pane edge")
assert(display_config.height == 4, "display must include every encoded row")
assert(vim.wo[display.win].winblend == 0, "occupied interval must not blend source cells")
local display_view = vim.api.nvim_win_call(display.win, vim.fn.winsaveview)
assert(display_view.topline == 1, "display must start at the first encoded row")
assert(display_view.leftcol == 0, "display must start at the minimap rail")

vim.api.nvim_buf_set_lines(map_buf, 2, -1, false, {})
manager.schedule({ lines = true, integrations = false, scrollbar = false })
wait_for(function()
	local shortened = manager.rendered_maps[map_win]
	return shortened
		and shortened.win == display.win
		and vim.api.nvim_win_is_valid(shortened.win)
		and vim.api.nvim_win_get_height(shortened.win) == 2
end, "display float did not shrink below the encoded minimap EOF")

map.close()
vim.wait(20, function()
	return false
end)
print("minimap opaque occupied-interval regression: ok")
