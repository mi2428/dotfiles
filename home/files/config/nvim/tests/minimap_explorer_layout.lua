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
local setup_explorer_layout = upvalue(specs[1].config, "setup_explorer_layout")

vim.o.columns = 120
vim.o.lines = 40
vim.cmd("botright 30vnew")
local explorer_win = vim.api.nvim_get_current_win()
local explorer_col = vim.api.nvim_win_get_position(explorer_win)[2]
local map_buf = vim.api.nvim_create_buf(false, true)
local map_win = vim.api.nvim_open_win(map_buf, false, {
	relative = "editor",
	anchor = "NE",
	row = 0,
	col = vim.o.columns,
	width = 12,
	height = 20,
	style = "minimal",
})

local explorer_visible = true
local original_snacks = package.loaded.snacks
package.loaded.snacks = {
	picker = {
		get = function(opts)
			assert(opts.source == "explorer", "minimap must only inspect Explorer pickers")
			if not explorer_visible then
				return {}
			end
			return {
				{
					layout = {
						root = {
							win = explorer_win,
							opts = { position = "right" },
						},
					},
				},
			}
		end,
	},
}

local refreshes = 0
local map = {
	current = { win_data = { [vim.api.nvim_get_current_tabpage()] = map_win } },
	refresh = function()
		refreshes = refreshes + 1
	end,
}

setup_explorer_layout(map)
assert(
	vim.wait(1000, function()
		return vim.api.nvim_win_get_config(map_win).col == explorer_col
	end),
	"minimap did not move left of the right-side Explorer"
)

vim.api.nvim_win_set_config(map_win, {
	relative = "editor",
	anchor = "NE",
	row = 0,
	col = vim.o.columns,
	width = 12,
	height = 20,
})
map.refresh()
assert(
	vim.wait(1000, function()
		return vim.api.nvim_win_get_config(map_win).col == explorer_col
	end),
	"minimap refresh did not preserve the Explorer offset"
)
assert(refreshes == 1, "minimap refresh wrapper did not call the original refresh")

explorer_visible = false
map.refresh()
assert(
	vim.wait(1000, function()
		return vim.api.nvim_win_get_config(map_win).col == vim.o.columns
	end),
	"minimap did not return to the editor edge after Explorer closed"
)

package.loaded.snacks = original_snacks
print("minimap Explorer layout regression: ok")
