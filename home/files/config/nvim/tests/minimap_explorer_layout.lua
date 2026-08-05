local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
vim.opt.runtimepath:prepend(nvim_root)
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
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

local specs = dofile(vim.fs.joinpath(nvim_root, "lua/plugins/minimap.lua"))
local setup_code_layout = upvalue(specs[1].config, "setup_code_layout")
local set_minimap_highlights = upvalue(specs[1].config, "set_minimap_highlights")

vim.o.columns = 120
vim.o.lines = 40
local source_win = vim.api.nvim_get_current_win()
local source_buf = vim.api.nvim_get_current_buf()
vim.wo[source_win].winbar = "Source"

vim.cmd("botright 30vnew")
local explorer_win = vim.api.nvim_get_current_win()
vim.bo[vim.api.nvim_win_get_buf(explorer_win)].filetype = "snacks_layout_box"
vim.api.nvim_set_current_win(source_win)

local map_buf = vim.api.nvim_create_buf(false, true)
local map_win = vim.api.nvim_open_win(map_buf, false, {
	relative = "editor",
	anchor = "NE",
	row = 0,
	col = vim.o.columns,
	width = 12,
	height = 30,
	style = "minimal",
})

local refreshes = 0
local map = {
	current = {
		buf_data = { source = source_buf },
		win_data = { [vim.api.nvim_get_current_tabpage()] = map_win },
	},
	refresh = function()
		refreshes = refreshes + 1
	end,
}

local function expected_geometry()
	local position = vim.api.nvim_win_get_position(source_win)
	return {
		row = position[1],
		col = position[2] + vim.api.nvim_win_get_width(source_win),
		height = vim.api.nvim_win_get_height(source_win),
	}
end

local function assert_geometry(message)
	local expected = expected_geometry()
	local config = vim.api.nvim_win_get_config(map_win)
	assert(config.row == expected.row, ("%s: row %d, expected %d"):format(message, config.row, expected.row))
	assert(config.col == expected.col, ("%s: col %d, expected %d"):format(message, config.col, expected.col))
	assert(
		config.height == expected.height,
		("%s: height %d, expected %d"):format(message, config.height, expected.height)
	)
end

setup_code_layout(map)
assert(
	vim.wait(1000, function()
		local expected = expected_geometry()
		local config = vim.api.nvim_win_get_config(map_win)
		return config.row == expected.row and config.col == expected.col and config.height == expected.height
	end),
	"minimap did not align to the source code area"
)

vim.api.nvim_win_set_config(map_win, {
	relative = "editor",
	anchor = "NE",
	row = 0,
	col = vim.o.columns,
	width = 12,
	height = 30,
})
map.refresh()
assert_geometry("refresh must immediately restore code-only geometry")
assert(refreshes == 1, "minimap refresh wrapper did not call the original refresh")

vim.api.nvim_set_current_win(source_win)
vim.cmd("botright 8new")
local terminal_win = vim.api.nvim_get_current_win()
vim.bo[vim.api.nvim_win_get_buf(terminal_win)].buftype = "nofile"
map.refresh()
assert_geometry("terminal split must shrink the minimap with the code window")

vim.api.nvim_win_close(terminal_win, true)
vim.api.nvim_win_close(explorer_win, true)
vim.api.nvim_set_current_win(source_win)
map.refresh()
assert_geometry("closing side layouts must expand the minimap with the code window")

local original_map = package.loaded["mini.map"]
package.loaded["mini.map"] = {
	gen_integration = {
		builtin_search = function()
			return function() end
		end,
		diagnostic = function()
			return function() end
		end,
		gitsigns = function()
			return function() end
		end,
	},
	gen_encode_symbols = {
		dot = function()
			return {}
		end,
	},
}
local opts = specs[1].opts()
package.loaded["mini.map"] = original_map
assert(opts.window.winblend == 0, "occupied minimap intervals must be fully opaque")
assert(opts.window.zindex > 20, "minimap must render above treesitter-context's zindex")

set_minimap_highlights()
local normal = vim.api.nvim_get_hl(0, { name = "MiniMapNormal", link = false })
local editor_normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
assert(normal.bg == editor_normal.bg, "MiniMapNormal must match Normal's background")
assert(not normal.blend or normal.blend == 0, "MiniMapNormal must not blend source cells into occupied intervals")
for _, group in ipairs({ "MiniMapSymbolLine", "MiniMapSymbolView", "MiniMapSymbolCount" }) do
	local highlight = vim.api.nvim_get_hl(0, { name = group, link = false })
	assert(highlight.bg == editor_normal.bg, group .. " must match Normal's background")
end
for _, group in ipairs({ "MiniMapDiagnosticError", "MiniMapSearch" }) do
	local highlight = vim.api.nvim_get_hl(0, { name = group, link = false })
	assert(highlight.bg ~= nil, group .. " must define its integration background")
	assert(not highlight.blend or highlight.blend == 0, group .. " must remain opaque")
end

vim.api.nvim_set_hl(0, "Normal", { fg = editor_normal.fg })
set_minimap_highlights()
for _, group in ipairs({ "MiniMapNormal", "MiniMapSymbolLine", "MiniMapSymbolView", "MiniMapSymbolCount" }) do
	local highlight = vim.api.nvim_get_hl(0, { name = group, link = false })
	assert(highlight.bg == nil, group .. " must inherit the terminal background when Normal has none")
end

local preview_win = vim.api.nvim_open_win(source_buf, true, {
	relative = "editor",
	row = 2,
	col = 2,
	width = 60,
	height = 20,
	style = "minimal",
})
vim.w[preview_win].dotfiles_glance_preview = true
local source_focus_count = 0
local focus_group = vim.api.nvim_create_augroup("dotfiles-minimap-transient-overlay-test", { clear = true })
vim.api.nvim_create_autocmd("WinEnter", {
	group = focus_group,
	callback = function()
		if vim.api.nvim_get_current_win() == source_win then
			source_focus_count = source_focus_count + 1
		end
	end,
})
map._dotfiles_resolve_filetype_source()
assert(vim.api.nvim_get_current_win() == preview_win, "source resolution left the Glance preview")
assert(source_focus_count == 0, "source resolution briefly focused the editor behind the Glance preview")
local overlay_events_settled = false
vim.schedule(function()
	overlay_events_settled = true
end)
assert(
	vim.wait(1000, function()
		return overlay_events_settled
	end),
	"transient overlay events did not settle"
)
vim.api.nvim_del_augroup_by_id(focus_group)
pcall(vim.api.nvim_del_augroup_by_name, "dotfiles-mini-map-code-layout")
vim.api.nvim_win_close(preview_win, true)
vim.api.nvim_win_close(map_win, true)
vim.api.nvim_buf_delete(map_buf, { force = true })
vim.wait(20, function()
	return false
end)

print("minimap code-area layout regression: ok")
