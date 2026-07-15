local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
local function lockfile_path()
	local preferred = vim.fn.expand("~/dotfiles/home/files/config/nvim/lazy-lock.json")
	if vim.uv.fs_stat(preferred) ~= nil then
		return preferred
	end

	return vim.fn.stdpath("data") .. "/lazy/lazy-lock.json"
end

if not vim.uv.fs_stat(lazypath) then
	local out = vim.fn.system({
		"git",
		"clone",
		"--filter=blob:none",
		"https://github.com/folke/lazy.nvim.git",
		"--branch=stable",
		lazypath,
	})
	if vim.v.shell_error ~= 0 then
		error("Failed to clone lazy.nvim:\n" .. out)
	end
end

vim.opt.rtp:prepend(lazypath)

require("lazy").setup("plugins", {
	lockfile = lockfile_path(),
	change_detection = {
		notify = false,
	},
	install = {
		colorscheme = { "catppuccin" },
	},
})
