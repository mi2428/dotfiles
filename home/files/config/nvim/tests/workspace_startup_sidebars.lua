local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
vim.opt.runtimepath:prepend(nvim_root)
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")

vim.env.NVIM_WORKSPACE_MODE = "1"
vim.cmd.args({ dotfiles_root })

local calls = {}
package.loaded["fzf-lua"] = {
	files = function(opts)
		calls.fzf = opts
		vim.cmd("botright vnew")
		calls.fzf_window = vim.api.nvim_get_current_win()
		vim.bo.filetype = "fzf"
	end,
}
_G.Snacks = {
	explorer = function(opts)
		calls.explorer = opts
	end,
}
package.loaded["config.sidebar"] = {
	open_aerial = function(opts)
		calls.aerial = opts
	end,
}
package.loaded["config.lazygit"] = {
	toggle = function()
		calls.lazygit = (calls.lazygit or 0) + 1
		vim.cmd("botright new")
		calls.lazygit_window = vim.api.nvim_get_current_win()
		vim.bo.filetype = "snacks_terminal"
	end,
}

local original_list_uis = vim.api.nvim_list_uis
vim.api.nvim_list_uis = function()
	return { {} }
end
dofile(vim.fs.joinpath(nvim_root, "lua/config/autocmds.lua"))
vim.api.nvim_exec_autocmds("VimEnter", { modeline = false })
assert(
	vim.wait(1000, function()
		return calls.fzf ~= nil
	end, 1),
	"workspace picker did not start"
)
assert(not calls.explorer, "workspace sidebars must wait for the picker source to initialize")
assert(
	vim.wait(1000, function()
		return calls.lazygit == 1
	end),
	"workspace startup did not finish"
)
vim.api.nvim_list_uis = original_list_uis

assert(
	calls.fzf and vim.fs.normalize(calls.fzf.cwd) == vim.fs.normalize(dotfiles_root),
	"workspace startup must open its file picker at the root"
)
assert(calls.explorer and calls.explorer.focus == false, "workspace Explorer must open without stealing focus")
assert(calls.explorer.watch == true, "workspace Explorer must retain filesystem watching")
assert(calls.aerial, "workspace startup must open Aerial")
assert(vim.api.nvim_win_is_valid(calls.aerial.source_win), "workspace Aerial must receive a valid editor source")
assert(calls.aerial.source_win ~= calls.fzf_window, "workspace Aerial must attach to the editor, not fzf")
assert(vim.api.nvim_get_current_win() == calls.fzf_window, "workspace startup must restore focus to fzf after LazyGit")
assert(vim.bo[vim.api.nvim_win_get_buf(calls.fzf_window)].filetype == "fzf", "workspace focus must remain in fzf")

print("workspace LazyGit and focused sidebars startup regression: ok")
