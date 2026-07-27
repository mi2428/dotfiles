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

local specs = dofile(vim.fs.joinpath(nvim_root, "lua/plugins/git.lua"))
local diffview = specs[2]
local set_diffview_highlights = upvalue(diffview.init, "set_diffview_highlights")

vim.api.nvim_set_hl(0, "DiffDelete", { fg = "#ff0000", bg = "#440000" })
set_diffview_highlights()
local filler = vim.api.nvim_get_hl(0, { name = "DiffviewDiffDeleteDim", link = false })
local deletion = vim.api.nvim_get_hl(0, { name = "DiffDelete", link = false })
assert(filler.fg == nil and filler.bg == nil, "Diffview alignment filler must be completely uncolored")
assert(deletion.fg ~= nil and deletion.bg ~= nil, "real deletion highlighting must remain intact")

local original_diffview = package.loaded.diffview
package.loaded.diffview = {
	setup = function()
		-- diffview.setup() creates this default link after the plugin's init hook.
		vim.api.nvim_set_hl(0, "DiffviewDiffDeleteDim", { link = "Comment" })
	end,
}
diffview.config(nil, diffview.opts)
package.loaded.diffview = original_diffview
filler = vim.api.nvim_get_hl(0, { name = "DiffviewDiffDeleteDim", link = false })
assert(filler.fg == nil and filler.bg == nil, "Diffview setup restored colored alignment filler")

vim.wo.fillchars = "diff:-"
diffview.opts.hooks.diff_buf_win_enter(vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win(), {})
assert(vim.wo.fillchars:find("diff: ", 1, true), "Diffview addition filler must render as a blank space")
assert(diffview.opts.enhanced_diff_hl, "Diffview must separate deletion lines from alignment filler")

print("Diffview blank filler regression: ok")
