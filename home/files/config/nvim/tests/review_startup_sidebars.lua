local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
vim.opt.runtimepath:prepend(nvim_root)
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")

vim.env.NVIM_REVIEW_MODE = "1"
vim.env.NVIM_REVIEW_BASE = "HEAD"
vim.env.NVIM_REVIEW_HEAD = "HEAD"
vim.env.NVIM_REVIEW_WORKTREE = dotfiles_root
vim.env.NVIM_REVIEW_REPO_ROOT = dotfiles_root

local calls = {}
package.loaded["snacks.explorer.git"] = {
	_update = function()
		return false
	end,
	update = function() end,
}
package.loaded.snacks = {
	explorer = function(opts)
		calls.explorer = opts
		if opts.on_show then
			opts.on_show()
		end
	end,
}
package.loaded["config.sidebar"] = {
	open_aerial = function(opts)
		calls.aerial = opts
	end,
}

local editor = vim.api.nvim_get_current_win()
local review = require("config.review")
assert(review.state, "review test environment did not initialize")
review.setup()
vim.api.nvim_exec_autocmds("VimEnter", { modeline = false })
assert(
	vim.wait(1000, function()
		return calls.aerial ~= nil
	end),
	"review startup did not open both sidebars"
)

assert(calls.explorer.cwd == dotfiles_root, "review Explorer must use the review worktree")
assert(calls.explorer.focus == false, "review Explorer must open without stealing focus")
assert(calls.aerial.source_win == editor, "review Aerial must attach to the review editor")
assert(vim.api.nvim_get_current_win() == editor, "review sidebars must preserve editor focus")

print("review Explorer and Aerial startup regression: ok")
