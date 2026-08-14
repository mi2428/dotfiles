local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
vim.opt.runtimepath:prepend(nvim_root)
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")

local specs = dofile(vim.fs.joinpath(nvim_root, "lua/plugins/folding.lua"))
assert(specs[2].opts.override_foldtext == false, "nvim-ufo must preserve native fold text rendering")
assert(specs[2].opts.fold_virt_text_handler == nil, "nvim-ufo must not overlay the folded line with virtual text")

dofile(vim.fs.joinpath(nvim_root, "lua/config/options.lua"))
assert(vim.wo.foldtext == "", "closed folds must render their first line normally")
vim.wo.foldmethod = "manual"
vim.wo.foldcolumn = "0"
vim.wo.number = false
vim.wo.relativenumber = false
vim.wo.signcolumn = "no"
vim.api.nvim_buf_set_lines(0, 0, -1, false, {
	"local function folded()",
	"  return true",
	"end",
	"plain line",
	"cursor line",
})
vim.api.nvim_win_set_cursor(0, { 5, 0 })
vim.fn.setreg("/", "folded")
vim.v.hlsearch = 1
vim.cmd.redraw({ bang = true })
local open_search_attr = vim.fn.screenattr(1, 16)

vim.cmd("1,3fold")
vim.cmd.redraw({ bang = true })
local closed_search_attr = vim.fn.screenattr(1, 16)
assert(closed_search_attr == open_search_attr, "closed folds must preserve search highlighting")

local far_column = math.min(70, vim.o.columns - 1)
local folded_attr = vim.fn.screenattr(1, far_column)
local plain_attr = vim.fn.screenattr(2, far_column)
assert(folded_attr ~= 0, "the folded row must have a screen highlight at the far edge")
assert(folded_attr ~= plain_attr, "the folded background must extend across the full text width")

print("folding style regression: ok")
