local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
vim.opt.runtimepath:prepend(nvim_root)
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")

local function assert_match(value, pattern, message)
	if not value:match(pattern) then
		error(("%s\npattern: %s\nactual:  %s"):format(message, pattern, value))
	end
end

vim.wo.winhighlight = "Normal:ErrorMsg"
dofile(vim.fs.joinpath(nvim_root, "lua/config/options.lua"))

local palette = require("config.catppuccin").palette()
local fold_column = vim.api.nvim_get_hl(0, { name = "FoldColumn", link = false })
assert(fold_column.fg == tonumber(palette.blue:sub(2), 16), "fold chevrons must use the palette's blue rail color")
assert(fold_column.bg ~= nil, "blank fold continuation cells must have a rail background")
assert(
	fold_column.bg ~= tonumber(palette.base:sub(2), 16),
	"the fold rail must remain visible against the editor background"
)

local left = vim.api.nvim_get_current_win()
local left_default = vim.wo[left].winhighlight
assert_match(left_default, "Normal:ErrorMsg", "existing window highlight overrides must be preserved")
assert_match(
	left_default,
	"CursorLine:DotfilesCursorLineDefault",
	"the first window must use default cursorline colors"
)
assert_match(
	left_default,
	"DotfilesCursorLineCodexNr:DotfilesCursorLineCodexNrDefault",
	"the first window must compose the Codex number color with the default cursorline scene"
)
assert(
	vim.api.nvim_get_hl(0, { name = "DotfilesCursorLineFoldDefault", link = false }).fg == fold_column.fg,
	"the current-line fold chevron must keep the fold rail foreground"
)

vim.api.nvim_set_hl(0, "FoldColumn", { fg = "#ff0000" })
vim.api.nvim_exec_autocmds("ColorScheme", { modeline = false })
local refreshed_fold_column = vim.api.nvim_get_hl(0, { name = "FoldColumn", link = false })
assert(refreshed_fold_column.fg == fold_column.fg, "colorscheme changes must restore the fold rail foreground")
assert(refreshed_fold_column.bg == fold_column.bg, "colorscheme changes must restore the fold rail background")

vim.cmd.vsplit()
local right = vim.api.nvim_get_current_win()
assert(
	vim.wait(1000, function()
		return vim.wo[right].winhighlight:match("CursorLine:DotfilesCursorLineDefault") ~= nil
	end),
	"the split window was not initialized"
)

vim.api.nvim_exec_autocmds("CmdlineEnter", { modeline = false })
assert_match(
	vim.wo[right].winhighlight,
	"CursorLine:DotfilesCursorLineCommand",
	"command mode must update the active split"
)
assert_match(
	vim.wo[right].winhighlight,
	"DotfilesCursorLineCodexNr:DotfilesCursorLineCodexNrCommand",
	"command mode must update the Codex number cursorline background"
)
assert(vim.wo[left].winhighlight == left_default, "command mode in one split must not update another split")

vim.api.nvim_exec_autocmds("CmdlineLeave", { modeline = false })
assert(
	vim.wait(1000, function()
		return vim.wo[right].winhighlight:match("CursorLine:DotfilesCursorLineDefault") ~= nil
	end),
	"leaving command mode did not restore the active split"
)
assert(vim.wo[left].winhighlight == left_default, "leaving command mode changed another split")

print("cursorline split regression: ok")
