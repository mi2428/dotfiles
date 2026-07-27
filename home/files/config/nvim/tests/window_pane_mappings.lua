local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
vim.opt.runtimepath:prepend(nvim_root)
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")

vim.o.columns = 160
vim.o.lines = 50
vim.o.splitbelow = true
vim.o.splitright = true
dofile(vim.fs.joinpath(nvim_root, "lua/config/keymaps.lua"))

local expected = {
	["<C-w>h"] = "<Cmd>wincmd h<CR>",
	["<C-w>j"] = "<Cmd>wincmd j<CR>",
	["<C-w>k"] = "<Cmd>wincmd k<CR>",
	["<C-w>l"] = "<Cmd>wincmd l<CR>",
}
for lhs, rhs in pairs(expected) do
	assert(vim.fn.maparg(lhs, "n") == rhs, lhs .. " does not match the tmux pane binding")
end
for _, lhs in ipairs({ "<C-w>H", "<C-w>J", "<C-w>K", "<C-w>L" }) do
	local mapping = vim.fn.maparg(lhs, "n", false, true)
	assert(mapping.callback ~= nil, lhs .. " is not mapped to directional pane resizing")
end

local function press(lhs)
	local keys = vim.api.nvim_replace_termcodes(lhs, true, false, true)
	vim.api.nvim_feedkeys(keys, "x", false)
end

local left = vim.api.nvim_get_current_win()
vim.cmd.vsplit()
local right = vim.api.nvim_get_current_win()
local original_width = vim.api.nvim_win_get_width(right)
press("<C-w>H")
assert(vim.api.nvim_win_get_width(right) == original_width + 5, "<C-w>H did not grow toward the left by five cells")
press("<C-w>L")
assert(vim.api.nvim_win_get_width(right) == original_width + 5, "<C-w>L must be a no-op at the right edge")
press("<C-w>h")
assert(vim.api.nvim_get_current_win() == left, "<C-w>h did not move to the left pane")
local left_width = vim.api.nvim_win_get_width(left)
press("<C-w>L")
assert(vim.api.nvim_win_get_width(left) == left_width + 5, "<C-w>L did not grow toward the right by five cells")
press("<C-w>l")
assert(vim.api.nvim_get_current_win() == right, "<C-w>l did not move to the right pane")

vim.cmd.split()
local lower = vim.api.nvim_get_current_win()
local original_height = vim.api.nvim_win_get_height(lower)
press("<C-w>K")
assert(vim.api.nvim_win_get_height(lower) == original_height + 5, "<C-w>K did not grow upward by five rows")
press("<C-w>J")
assert(vim.api.nvim_win_get_height(lower) == original_height + 5, "<C-w>J must be a no-op at the bottom edge")
press("<C-w>k")
local upper = vim.api.nvim_get_current_win()
local upper_height = vim.api.nvim_win_get_height(upper)
press("<C-w>J")
assert(vim.api.nvim_win_get_height(upper) == upper_height + 5, "<C-w>J did not grow downward by five rows")

print("tmux-style Neovim pane mappings: ok")
