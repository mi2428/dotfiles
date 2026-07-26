local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
vim.opt.runtimepath:prepend(nvim_root)
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")

local specs = dofile(vim.fs.joinpath(nvim_root, "lua/plugins/folding.lua"))
local handler = assert(specs[2].opts.fold_virt_text_handler, "nvim-ufo must define a fold text handler")
local original = {
	{ "local ", "Keyword" },
	{ "function folded()", "Function" },
}
local rendered = handler(vim.deepcopy(original), 1, 3, 80, function(text)
	return text
end)
assert(vim.deep_equal(rendered, original), "fold text must preserve the first line without adding a suffix")
assert(not vim.iter(rendered):any(function(chunk)
	return chunk[1]:find("⋯", 1, true) ~= nil
end), "fold text must not append ufo's ellipsis")

dofile(vim.fs.joinpath(nvim_root, "lua/config/options.lua"))
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
vim.cmd("1,3fold")
vim.api.nvim_win_set_cursor(0, { 5, 0 })
vim.cmd.redraw({ bang = true })

local far_column = math.min(70, vim.o.columns - 1)
local folded_attr = vim.fn.screenattr(1, far_column)
local plain_attr = vim.fn.screenattr(2, far_column)
assert(folded_attr ~= 0, "the folded row must have a screen highlight at the far edge")
assert(folded_attr ~= plain_attr, "the folded background must extend across the full text width")

print("folding style regression: ok")
