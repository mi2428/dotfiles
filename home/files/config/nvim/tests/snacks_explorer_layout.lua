local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
vim.opt.runtimepath:prepend(nvim_root)
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")

local specs = dofile(vim.fs.joinpath(nvim_root, "lua/plugins/ui.lua"))
local snacks
for _, spec in ipairs(specs) do
	if spec[1] == "folke/snacks.nvim" then
		snacks = spec
		break
	end
end
assert(snacks, "Snacks plugin spec was not found")

local explorer = snacks.opts.picker.sources.explorer
local layout = explorer.layout.layout
assert(layout.position == "right", "Explorer must remain on the right")
assert(explorer.layout.preview == false, "Explorer preview must remain hidden by default")
assert(vim.deep_equal(explorer.layout.hidden, { "input" }), "Explorer input must start hidden")
assert(vim.deep_equal(explorer.layout.auto_hide, { "input" }), "Explorer input must hide again when it loses focus")
assert(layout[1].win == "list", "Explorer file list must fill the upper area")
assert(layout[2].win == "preview", "Explorer preview must open above the search input")
assert(layout[3].win == "input", "Explorer search input must stay at the bottom")
assert(layout[3].height == 1, "Explorer search input must remain one line high")

print("Snacks Explorer on-demand bottom input regression: ok")
