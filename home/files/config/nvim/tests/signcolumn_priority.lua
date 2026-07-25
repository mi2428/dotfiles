local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
vim.opt.runtimepath:prepend(vim.fs.joinpath(dotfiles_root, "home/files/config/nvim"))
package.path = table.concat({
	vim.fs.joinpath(dotfiles_root, "home/files/config/nvim/lua/?.lua"),
	vim.fs.joinpath(dotfiles_root, "home/files/config/nvim/lua/?/init.lua"),
	package.path,
}, ";")

local specs = dofile(vim.fs.joinpath(dotfiles_root, "home/files/config/nvim/lua/plugins/git.lua"))
local priority = assert(specs[1].opts.sign_priority, "Gitsigns priority must be configured")
assert(priority > 30, "Gitsigns must outrank Codex and diagnostic signs")

vim.opt.signcolumn = "yes:2"
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "sign priority regression" })
vim.bo.modified = false

local git_namespace = vim.api.nvim_create_namespace("dotfiles-test-gitsigns")
local diagnostic_namespace = vim.api.nvim_create_namespace("dotfiles-test-diagnostics")
local codex_namespace = vim.api.nvim_create_namespace("dotfiles-test-codex")

vim.api.nvim_buf_set_extmark(0, git_namespace, 0, 0, {
	priority = priority,
	sign_text = "G ",
})

local function rendered_signs()
	return vim.api.nvim_eval_statusline("%s", {
		maxwidth = 4,
		use_statuscol_lnum = 1,
		winid = vim.api.nvim_get_current_win(),
	}).str
end

local git_only = rendered_signs()
vim.api.nvim_buf_set_extmark(0, diagnostic_namespace, 0, 0, {
	priority = 10,
	sign_text = "D ",
})
local with_diagnostic = rendered_signs()

assert(git_only:find("G", 1, true) == with_diagnostic:find("G", 1, true), "diagnostics must not move Gitsigns")
assert(with_diagnostic == "G D ", "diagnostics must use the secondary sign slot")

vim.api.nvim_buf_set_extmark(0, codex_namespace, 0, 0, {
	priority = 30,
	sign_text = "C ",
})
assert(rendered_signs() == "G C ", "Codex must share the secondary slot and outrank diagnostics")

print("signcolumn priority regression: ok")
