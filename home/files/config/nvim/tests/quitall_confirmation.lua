local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
vim.opt.runtimepath:prepend(nvim_root)
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")

dofile(vim.fs.joinpath(nvim_root, "lua/config/commands.lua"))

assert(vim.fn.maparg("q", "c", true) == "", ":q must remain an unmodified built-in command")
for _, command in ipairs({ "qa", "qall", "quitall" }) do
	local mapping = vim.fn.maparg(command, "c", true, true)
	assert(mapping.expr == 1 and mapping.callback ~= nil, ":" .. command .. " does not require confirmation")
end

local original_confirm = vim.fn.confirm
local confirmation
vim.fn.confirm = function(prompt, choices, default)
	confirmation = { prompt = prompt, choices = choices, default = default }
	return 2
end
vim.cmd.DotfilesQuitAll()
vim.fn.confirm = original_confirm

assert(confirmation.prompt == "Quit all Neovim windows?", "quit-all confirmation prompt changed")
assert(confirmation.choices == "&Yes\n&No", "quit-all confirmation must offer y/N")
assert(confirmation.default == 2, "quit-all confirmation must default to No")
assert(vim.api.nvim_get_current_win() ~= 0, "declining quit-all still exited Neovim")

print("quit-all confirmation regression: ok")
