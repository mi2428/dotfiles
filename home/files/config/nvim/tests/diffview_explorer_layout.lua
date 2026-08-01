local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
vim.opt.runtimepath:prepend(nvim_root)
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")
package.loaded["config.diffview_snacks_panel"] = nil
local searched_panel = assert(package.searchpath("config.diffview_snacks_panel", package.path))
local expected_panel = vim.fs.joinpath(nvim_root, "lua/config/diffview_snacks_panel.lua")
assert(
	vim.uv.fs_realpath(searched_panel) == vim.uv.fs_realpath(expected_panel),
	("Diffview panel search resolved %s, expected %s"):format(searched_panel, expected_panel)
)
local panel = require("config.diffview_snacks_panel")
local panel_module = assert(debug.getinfo(panel._picker_options, "S").source):gsub("^@", "")
assert(
	vim.uv.fs_realpath(panel_module) == vim.uv.fs_realpath(expected_panel),
	("Diffview panel loaded from %s, expected %s"):format(panel_module, expected_panel)
)

local function picker_root(source, tab)
	for _, picker in ipairs(require("snacks").picker.get({ source = source, tab = false })) do
		local root = picker.layout and picker.layout.root
		if
			root
			and root.win
			and vim.api.nvim_win_is_valid(root.win)
			and vim.api.nvim_win_get_tabpage(root.win) == tab
		then
			return root.win
		end
	end
end

local function filetype_window(tab, filetype)
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
		if vim.api.nvim_win_get_config(win).relative == "" then
			local buf = vim.api.nvim_win_get_buf(win)
			if vim.bo[buf].filetype == filetype then
				return win
			end
		end
	end
end

vim.o.columns = 200
vim.o.lines = 80
vim.o.cmdheight = 0
local dashboard = require("snacks.dashboard").open({ buf = 0, win = 0 })
assert(dashboard.win == vim.api.nvim_get_current_win(), "Dashboard must own the initial normal window")

vim.cmd("DiffviewOpen HEAD~1")
assert(
	vim.wait(5000, function()
		local tab = vim.api.nvim_get_current_tabpage()
		return picker_root("diffview_files", tab) ~= nil and filetype_window(tab, "aerial") ~= nil
	end),
	"Diffview did not open its Changes picker and Aerial sidebar"
)

local tab = vim.api.nvim_get_current_tabpage()
local view = assert(require("diffview.lib").get_current_view(), "Diffview must own the current tab")
local main_win = view.cur_layout:get_main_win().id
local main_height = vim.api.nvim_win_get_height(main_win)
local changes_win = assert(picker_root("diffview_files", tab), "Diffview Changes picker is missing")
local changes_meta = vim.w[changes_win].snacks_win
assert(changes_meta and changes_meta.position == "diffview_files", "Diffview picker equalize identity is missing")
assert(vim.o.cmdheight == 0, "Diffview startup must preserve the hidden native command line")

require("config.sidebar").toggle_explorer()
assert(
	vim.wait(3000, function()
		local explorer = picker_root("explorer", tab)
		local aerial = filetype_window(tab, "aerial")
		if not (explorer and aerial) then
			return false
		end
		local explorer_position = vim.fn.win_screenpos(explorer)
		local aerial_position = vim.fn.win_screenpos(aerial)
		return vim.o.cmdheight == 0
			and vim.api.nvim_win_get_height(main_win) == main_height
			and vim.api.nvim_win_get_height(changes_win) == main_height
			and explorer_position[2] == aerial_position[2]
			and explorer_position[1] < aerial_position[1]
			and vim.api.nvim_win_get_height(explorer) + vim.api.nvim_win_get_height(aerial) + 1 == main_height
	end),
	"Explorer did not settle beside Diffview without expanding 'cmdheight'"
)

local explorer_win = assert(picker_root("explorer", tab), "Explorer picker is missing")
local aerial_win = assert(filetype_window(tab, "aerial"), "Aerial sidebar is missing")
local explorer_pos = vim.fn.win_screenpos(explorer_win)
local aerial_pos = vim.fn.win_screenpos(aerial_win)
assert(vim.o.cmdheight == 0, "Explorer must not expand the native command-line area")
assert(vim.api.nvim_win_get_height(main_win) == main_height, "Explorer must not shorten the Diffview editors")
assert(
	vim.api.nvim_win_get_height(changes_win) == main_height,
	"the Diffview Changes column must regain full height after Aerial moves"
)
assert(explorer_pos[2] == aerial_pos[2] and explorer_pos[1] < aerial_pos[1], "Explorer and Aerial must stack")
assert(
	vim.api.nvim_win_get_height(explorer_win) + vim.api.nvim_win_get_height(aerial_win) + 1 == main_height,
	"the Explorer/Aerial stack must fill the editor height"
)
assert(filetype_window(tab, "snacks_dashboard") == nil, "Dashboard must remain outside the Diffview tab")

require("config.sidebar").toggle_explorer()
assert(
	vim.wait(3000, function()
		if picker_root("explorer", tab) ~= nil then
			return false
		end
		local aerial = filetype_window(tab, "aerial")
		if not aerial then
			return false
		end
		local current_changes_pos = vim.fn.win_screenpos(changes_win)
		local current_aerial_pos = vim.fn.win_screenpos(aerial)
		return vim.o.cmdheight == 0
			and current_changes_pos[2] == current_aerial_pos[2]
			and current_changes_pos[1] < current_aerial_pos[1]
			and vim.api.nvim_win_get_height(changes_win) + vim.api.nvim_win_get_height(aerial) + 1 == main_height
	end),
	"Explorer did not close and restore the Changes/Aerial stack"
)

aerial_win = assert(filetype_window(tab, "aerial"), "Aerial must remain after Explorer closes")
local changes_pos = vim.fn.win_screenpos(changes_win)
aerial_pos = vim.fn.win_screenpos(aerial_win)
assert(vim.o.cmdheight == 0, "closing Explorer must preserve the hidden native command line")
assert(changes_pos[2] == aerial_pos[2] and changes_pos[1] < aerial_pos[1], "Aerial must return below Changes")
assert(
	vim.api.nvim_win_get_height(changes_win) + vim.api.nvim_win_get_height(aerial_win) + 1 == main_height,
	"the restored Changes/Aerial stack must fill the editor height"
)

print("Diffview Explorer command-height regression: ok")
