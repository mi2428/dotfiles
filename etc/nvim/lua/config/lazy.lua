local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"

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
	lockfile = vim.fn.stdpath("config") .. "/lazy-lock.json",
	change_detection = {
		notify = false,
	},
	install = {
		colorscheme = { "habamax" },
	},
})
