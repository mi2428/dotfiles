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
vim.o.timeoutlen = 25
dofile(vim.fs.joinpath(nvim_root, "lua/config/keymaps.lua"))

local expected = {
	["<C-w>\\"] = "<Cmd>vsplit<CR>",
	["<C-w>h"] = "<Cmd>wincmd h<CR>",
	["<C-w>j"] = "<Cmd>wincmd j<CR>",
	["<C-w>k"] = "<Cmd>wincmd k<CR>",
	["<C-w>l"] = "<Cmd>wincmd l<CR>",
}
for lhs, rhs in pairs(expected) do
	assert(vim.fn.maparg(lhs, "n") == rhs, lhs .. " does not match the tmux pane binding")
end
assert(vim.fn.maparg("<C-w>|", "n") == "", "<C-w>| still overrides Neovim's maximum-width command")
for _, lhs in ipairs({ "<C-w>H", "<C-w>J", "<C-w>K", "<C-w>L" }) do
	local mapping = vim.fn.maparg(lhs, "n", false, true)
	assert(mapping.rhs:find("dotfiles%-pane%-resize"), lhs .. " is not mapped to directional pane resizing")
	assert(mapping.rhs:find("dotfiles%-pane%-resize%-repeat"), lhs .. " does not enter resize repeat mode")
end

local function press(lhs)
	local keys = vim.api.nvim_replace_termcodes(lhs, true, false, true)
	vim.api.nvim_feedkeys(keys, "x", false)
end

local left = vim.api.nvim_get_current_win()
vim.cmd.vsplit()
local right = vim.api.nvim_get_current_win()
local original_width = vim.api.nvim_win_get_width(right)
press("<C-w>H<Esc>")
assert(vim.api.nvim_win_get_width(right) == original_width + 5, "<C-w>H did not grow toward the left by five cells")
assert(vim.o.timeoutlen == 25, "pane resize repeat mode did not restore timeoutlen")
press("<C-w>L<Esc>")
assert(vim.api.nvim_win_get_width(right) == original_width, "<C-w>L did not move the separator right at the outer edge")
press("<C-w>h")
assert(vim.api.nvim_get_current_win() == left, "<C-w>h did not move to the left pane")
local left_width = vim.api.nvim_win_get_width(left)
press("<C-w>H<Esc>")
assert(vim.api.nvim_win_get_width(left) == left_width - 5, "<C-w>H did not move the separator left at the outer edge")
press("<C-w>L<Esc>")
assert(vim.api.nvim_win_get_width(left) == left_width, "<C-w>L did not grow toward the right by five cells")

press("<C-w>HHHH<Esc>")
assert(vim.api.nvim_win_get_width(left) == left_width - 20, "<C-w>HHHH did not repeat four five-cell resizes")
press("<C-w>HlH")
assert(vim.api.nvim_win_get_width(left) == left_width - 25, "a non-resize key did not leave pane resize repeat mode")
press("<C-w>l")
assert(vim.api.nvim_get_current_win() == right, "<C-w>l did not move to the right pane")

vim.cmd.split()
local lower = vim.api.nvim_get_current_win()
local original_height = vim.api.nvim_win_get_height(lower)
press("<C-w>K<Esc>")
assert(vim.api.nvim_win_get_height(lower) == original_height + 5, "<C-w>K did not grow upward by five rows")
press("<C-w>J<Esc>")
assert(
	vim.api.nvim_win_get_height(lower) == original_height,
	"<C-w>J did not move the separator down at the outer edge"
)
press("<C-w>k")
local upper = vim.api.nvim_get_current_win()
local upper_height = vim.api.nvim_win_get_height(upper)
press("<C-w>K<Esc>")
assert(vim.api.nvim_win_get_height(upper) == upper_height - 5, "<C-w>K did not move the separator up at the outer edge")
press("<C-w>J<Esc>")
assert(vim.api.nvim_win_get_height(upper) == upper_height, "<C-w>J did not grow downward by five rows")

vim.cmd.only()
local leftmost = vim.api.nvim_get_current_win()
vim.cmd.vsplit()
local middle = vim.api.nvim_get_current_win()
vim.cmd.vsplit()
local rightmost = vim.api.nvim_get_current_win()
press("<C-w>h")
assert(vim.api.nvim_get_current_win() == middle, "failed to focus the middle pane")
local three_pane_widths = {
	left = vim.api.nvim_win_get_width(leftmost),
	middle = vim.api.nvim_win_get_width(middle),
	right = vim.api.nvim_win_get_width(rightmost),
}
press("<C-w>HL<Esc>")
assert(vim.api.nvim_win_get_width(leftmost) == three_pane_widths.left - 5, "H moved the wrong middle-pane edge")
assert(
	vim.api.nvim_win_get_width(middle) == three_pane_widths.middle + 10,
	"HL did not grow both sides of the middle pane"
)
assert(vim.api.nvim_win_get_width(rightmost) == three_pane_widths.right - 5, "L moved the wrong middle-pane edge")

press("<Plug>(dotfiles-pane-resize-h)")
assert(vim.o.timeoutlen == 500, "pane resize repeat mode does not match tmux's 500 ms repeat-time")
press("<Plug>(dotfiles-pane-resize-repeat)<Esc>")
assert(vim.o.timeoutlen == 25, "pane resize timeout did not restore the normal timeoutlen")

print("tmux-style Neovim pane mappings: ok")
