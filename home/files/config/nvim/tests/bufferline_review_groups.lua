local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
vim.opt.runtimepath:prepend(nvim_root)
vim.opt.runtimepath:append(vim.fs.joinpath(vim.fn.stdpath("data"), "lazy/catppuccin"))
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")

local specs = dofile(vim.fs.joinpath(nvim_root, "lua/plugins/ui.lua"))
local bufferline
for _, spec in ipairs(specs) do
	if spec[1] == "akinsho/bufferline.nvim" then
		bufferline = spec
		break
	end
end
assert(bufferline, "bufferline plugin spec was not found")

local original_review_mode = vim.env.NVIM_REVIEW_MODE
vim.env.NVIM_REVIEW_MODE = "1"
local review_opts = bufferline.opts()
local groups = review_opts.options.groups
assert(groups.options.toggle_hidden_on_enter == false, "review groups must stay collapsed on initial BufEnter")
assert(groups.items[1].name == "docs" and groups.items[1].hidden, "docs must start collapsed in review mode")
assert(groups.items[2].name == "tests" and groups.items[2].hidden, "tests must start collapsed in review mode")

vim.env.NVIM_REVIEW_MODE = nil
local normal_opts = bufferline.opts()
assert(
	normal_opts.options.groups.options.toggle_hidden_on_enter,
	"normal buffers must retain automatic group expansion"
)
assert(not normal_opts.options.groups.items[1].hidden, "docs must remain expanded outside review mode")
assert(not normal_opts.options.groups.items[2].hidden, "tests must remain expanded outside review mode")

vim.env.NVIM_REVIEW_MODE = original_review_mode
print("bufferline review groups regression: ok")
