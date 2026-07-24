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

local left = vim.api.nvim_get_current_win()
local left_default = vim.wo[left].winhighlight
assert_match(left_default, "Normal:ErrorMsg", "existing window highlight overrides must be preserved")
assert_match(
	left_default,
	"CursorLine:DotfilesCursorLineDefault",
	"the first window must use default cursorline colors"
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
