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
local function blend(fg, bg, alpha)
	local function channel(hex, offset)
		return tonumber(hex:sub(offset, offset + 1), 16)
	end

	local channels = {}
	for offset = 2, 6, 2 do
		channels[#channels + 1] = math.floor((alpha * channel(fg, offset)) + ((1 - alpha) * channel(bg, offset)) + 0.5)
	end
	return ("#%02x%02x%02x"):format(unpack(channels))
end

local fold_column = vim.api.nvim_get_hl(0, { name = "FoldColumn", link = false })
assert(fold_column.fg == tonumber(palette.blue:sub(2), 16), "fold chevrons must use the palette's blue rail color")
assert(fold_column.bg ~= nil, "blank fold continuation cells must have a rail background")
assert(
	fold_column.bg ~= tonumber(palette.base:sub(2), 16),
	"the fold rail must remain visible against the editor background"
)
local fold_open = vim.api.nvim_get_hl(0, { name = "DotfilesFoldOpen", link = false })
local fold_closed = vim.api.nvim_get_hl(0, { name = "DotfilesFoldClosed", link = false })
local fold_depth = vim.api.nvim_get_hl(0, { name = "DotfilesFoldDepth", link = false })
assert(fold_open.fg == tonumber(palette.sapphire:sub(2), 16), "open folds must use Mocha sapphire")
assert(fold_closed.fg == tonumber(palette.mauve:sub(2), 16), "closed folds must use Mocha mauve")
assert(fold_depth.fg == tonumber(palette.surface2:sub(2), 16), "fold depths must use muted Mocha surface2")
assert(fold_open.bg == fold_column.bg, "open fold signs must retain the rail background")
assert(fold_closed.bg == fold_column.bg, "closed fold signs must retain the rail background")
assert(fold_depth.bg == fold_column.bg, "fold depth labels must retain the rail background")
local folded = vim.api.nvim_get_hl(0, { name = "Folded", link = false })
local folded_background = tonumber(blend(palette.blue, palette.base, 0.18):sub(2), 16)
assert(folded.bg == folded_background, "closed folds must use the emphasized full-width blue wash")

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
	"DotfilesStatuscolumnMarker:DotfilesStatuscolumnMarkerDefault",
	"the first window must use default relative-number marker colors"
)
assert_match(
	left_default,
	"DotfilesCursorLineCodexNr:DotfilesCursorLineCodexNrDefault",
	"the first window must compose the Codex number color with the default cursorline scene"
)
assert_match(
	left_default,
	"DotfilesCursorLineFoldOpen:DotfilesCursorLineFoldOpenDefault",
	"open fold signs on the cursor line must use scene-specific backgrounds"
)
assert_match(
	left_default,
	"DotfilesCursorLineFoldClosed:DotfilesCursorLineFoldClosedDefault",
	"closed fold signs on the cursor line must use scene-specific backgrounds"
)
assert_match(
	left_default,
	"DotfilesCursorLineFoldDepth:DotfilesCursorLineFoldDepthDefault",
	"fold depth labels on the cursor line must use scene-specific backgrounds"
)
assert(
	vim.api.nvim_get_hl(0, { name = "DotfilesCursorLineFoldDefault", link = false }).fg == fold_column.fg,
	"the current-line fold chevron must keep the fold rail foreground"
)
assert(
	vim.api.nvim_get_hl(0, { name = "DotfilesCursorLineFoldOpenDefault", link = false }).fg == fold_open.fg,
	"the current-line open sign must remain sapphire"
)
assert(
	vim.api.nvim_get_hl(0, { name = "DotfilesCursorLineFoldClosedDefault", link = false }).fg == fold_closed.fg,
	"the current-line closed sign must remain mauve"
)
assert(
	vim.api.nvim_get_hl(0, { name = "DotfilesCursorLineFoldDepthDefault", link = false }).fg == fold_depth.fg,
	"the current-line fold depth must remain muted"
)

vim.api.nvim_set_hl(0, "FoldColumn", { fg = "#ff0000" })
vim.api.nvim_set_hl(0, "DotfilesFoldOpen", { fg = "#ff0000" })
vim.api.nvim_set_hl(0, "DotfilesFoldClosed", { fg = "#ff0000" })
vim.api.nvim_set_hl(0, "DotfilesFoldDepth", { fg = "#ff0000" })
vim.api.nvim_set_hl(0, "Folded", { bg = "#ff0000" })
vim.api.nvim_exec_autocmds("ColorScheme", { modeline = false })
local refreshed_fold_column = vim.api.nvim_get_hl(0, { name = "FoldColumn", link = false })
assert(refreshed_fold_column.fg == fold_column.fg, "colorscheme changes must restore the fold rail foreground")
assert(refreshed_fold_column.bg == fold_column.bg, "colorscheme changes must restore the fold rail background")
assert(
	vim.api.nvim_get_hl(0, { name = "DotfilesFoldOpen", link = false }).fg == fold_open.fg,
	"colorscheme changes must restore the open fold color"
)
assert(
	vim.api.nvim_get_hl(0, { name = "DotfilesFoldClosed", link = false }).fg == fold_closed.fg,
	"colorscheme changes must restore the closed fold color"
)
assert(
	vim.api.nvim_get_hl(0, { name = "DotfilesFoldDepth", link = false }).fg == fold_depth.fg,
	"colorscheme changes must restore the fold depth color"
)
assert(
	vim.api.nvim_get_hl(0, { name = "Folded", link = false }).bg == folded_background,
	"colorscheme changes must restore the full-width folded-line background"
)

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
	"DotfilesStatuscolumnMarker:DotfilesStatuscolumnMarkerCommand",
	"command mode must update the relative-number marker colors"
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
