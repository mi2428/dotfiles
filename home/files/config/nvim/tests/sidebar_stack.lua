local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
vim.opt.runtimepath:prepend(nvim_root)
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")

local specs = dofile(vim.fs.joinpath(nvim_root, "lua/plugins/ui.lua"))
local aerial_spec
local snacks_spec
for _, spec in ipairs(specs) do
	if spec[1] == "stevearc/aerial.nvim" then
		aerial_spec = spec
	elseif spec[1] == "folke/snacks.nvim" then
		snacks_spec = spec
	end
end

local function find_key(spec, lhs)
	for _, key in ipairs(spec.keys or {}) do
		if key[1] == lhs then
			return key
		end
	end
end

local aerial_key = assert(find_key(aerial_spec, "<leader>s"), "<leader>s must toggle Aerial")
local explorer_key = assert(find_key(snacks_spec, "<leader>o"), "<leader>o must toggle Explorer")
assert(find_key(aerial_spec, "<leader>o") == nil, "Aerial must not shadow the Explorer toggle")
assert(find_key(snacks_spec, "<leader>e") == nil, "the old Explorer toggle must be removed")

local calls = {}
local real_sidebar = package.loaded["config.sidebar"]
package.loaded["config.sidebar"] = {
	toggle_aerial = function()
		calls.aerial = (calls.aerial or 0) + 1
	end,
	toggle_explorer = function()
		calls.explorer = (calls.explorer or 0) + 1
	end,
}
aerial_key[2]()
explorer_key[2]()
assert(calls.aerial == 1, "<leader>s did not call the Aerial sidebar toggle")
assert(calls.explorer == 1, "<leader>o did not call the Explorer sidebar toggle")
package.loaded["config.sidebar"] = real_sidebar

vim.o.columns = 160
vim.o.lines = 50
vim.o.splitright = true
local editor = vim.api.nvim_get_current_win()
vim.cmd.vnew()
local explorer = vim.api.nvim_get_current_win()
vim.bo.filetype = "snacks_layout_box"
vim.api.nvim_win_set_width(explorer, 40)
vim.cmd.vnew()
local aerial = vim.api.nvim_get_current_win()
vim.bo.filetype = "aerial"

local layout_updates = 0
local picker_sources = {}
local fake_picker = {
	closed = false,
	layout = {
		root = { win = explorer },
		update = function()
			layout_updates = layout_updates + 1
		end,
	},
}
local real_snacks = package.loaded.snacks
package.loaded.snacks = {
	picker = {
		get = function(opts)
			picker_sources[#picker_sources + 1] = opts.source
			return opts.source == "diffview_files" and { fake_picker } or {}
		end,
	},
}
package.loaded["config.sidebar"] = nil
local sidebar = require("config.sidebar")
assert(sidebar.width == 40, "Aerial sidebar width must remain the shared 40-column layout cap")
sidebar.sync()
assert(
	picker_sources[1] == "explorer" and picker_sources[2] == "diffview_files",
	"the sidebar stack must discover both standard Explorer and the Diffview picker"
)

local explorer_position = vim.fn.win_screenpos(explorer)
local aerial_position = vim.fn.win_screenpos(aerial)
assert(
	explorer_position[2] == aerial_position[2],
	"Explorer and Aerial must share one sidebar column: " .. vim.inspect(vim.fn.winlayout())
)
assert(explorer_position[1] < aerial_position[1], "Explorer must be above Aerial")
assert(vim.api.nvim_win_get_width(explorer) == vim.api.nvim_win_get_width(aerial), "sidebar widths must match")
assert(
	math.abs(vim.api.nvim_win_get_height(explorer) - vim.api.nvim_win_get_height(aerial)) <= 1,
	"stacked sidebar panes must split the available height evenly"
)
assert(vim.api.nvim_win_get_width(editor) > 40, "the editor must remain beside the stacked sidebar")
assert(layout_updates == 1, "stacking must refresh the nested Snacks picker layout")

vim.api.nvim_win_close(aerial, true)
sidebar.sync()
assert(
	vim.api.nvim_win_get_height(explorer) == vim.api.nvim_win_get_height(editor),
	"Explorer must regain full height after Aerial closes"
)
assert(layout_updates == 2, "expanding Explorer must refresh its nested picker layout")

package.loaded.snacks.picker.get = function()
	return {}
end
vim.api.nvim_win_set_width(explorer, 55)
sidebar.sync()
assert(vim.api.nvim_win_get_width(explorer) == 55, "a non-Explorer Snacks layout box must not be resized as a sidebar")

local aerial_open
local real_aerial = package.loaded.aerial
package.loaded.aerial = {
	open = function(opts)
		aerial_open = { opts = opts, source = vim.api.nvim_get_current_win() }
	end,
}
vim.api.nvim_set_current_win(explorer)
assert(sidebar.open_aerial({ source_win = editor }), "startup Aerial failed to open")
assert(aerial_open.source == editor, "startup Aerial must attach to the requested editor window")
assert(aerial_open.opts.focus == false, "startup Aerial must not steal focus")
assert(vim.api.nvim_get_current_win() == explorer, "startup Aerial must restore the previously focused window")
package.loaded.aerial = real_aerial

local floating_aerial_buf = vim.api.nvim_create_buf(false, true)
local floating_aerial = vim.api.nvim_open_win(floating_aerial_buf, false, {
	relative = "editor",
	row = 1,
	col = 1,
	width = 55,
	height = 10,
	style = "minimal",
})
vim.bo[floating_aerial_buf].filetype = "aerial"
sidebar.sync()
assert(
	vim.api.nvim_win_get_width(floating_aerial) == 55,
	"sidebar sync must not resize an Aerial embedded in a floating layout"
)
vim.api.nvim_win_close(floating_aerial, true)

package.loaded.snacks = real_snacks
package.loaded["config.sidebar"] = real_sidebar
print("stacked Explorer and Aerial sidebar regression: ok")
