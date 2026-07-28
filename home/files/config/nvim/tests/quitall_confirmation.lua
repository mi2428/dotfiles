local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
vim.opt.runtimepath:prepend(nvim_root)
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")

local commands = dofile(vim.fs.joinpath(nvim_root, "lua/config/commands.lua"))

assert(vim.fn.maparg("q", "c", true) == "", ":q must remain an unmodified built-in command")
for _, command in ipairs({ "qa", "qall", "quitall" }) do
	local mapping = vim.fn.maparg(command, "c", true, true)
	assert(mapping.expr == 1 and mapping.callback ~= nil, ":" .. command .. " does not require confirmation")
end

assert(not commands.should_confirm_quit_all(), "an empty Neovim session must skip quit-all confirmation")
vim.api.nvim_buf_set_name(0, "/tmp/dotfiles-quitall-confirmation.lua")
assert(commands.should_confirm_quit_all(), "a normal file buffer must retain quit-all confirmation")

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

vim.api.nvim_buf_set_name(0, "")
local original_tab = vim.api.nvim_get_current_tabpage()
vim.cmd.tabnew()
local diffview_tab = vim.api.nvim_get_current_tabpage()
local left_win = vim.api.nvim_get_current_win()
local left_buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_name(left_buf, "/tmp/dotfiles-diffview-left.lua")
vim.cmd.vnew()
local right_win = vim.api.nvim_get_current_win()
local right_buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_name(right_buf, "/tmp/dotfiles-diffview-right.lua")

local original_diffview_lib = package.loaded["diffview.lib"]
local layout = {
	windows = { { id = left_win }, { id = right_win } },
	files = function()
		return { { bufnr = left_buf }, { bufnr = right_buf } }
	end,
}
package.loaded["diffview.lib"] = {
	get_current_view = function()
		return { tabpage = diffview_tab, cur_layout = layout, files = { sets = {} } }
	end,
}
assert(not commands.should_confirm_quit_all(), "Diffview-only buffers must skip quit-all confirmation")

local hidden = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(hidden, "/tmp/dotfiles-other-buffer.lua")
assert(commands.should_confirm_quit_all(), "a hidden non-Diffview buffer must retain quit-all confirmation")
vim.api.nvim_buf_delete(hidden, { force = true })

vim.api.nvim_set_current_tabpage(original_tab)
vim.api.nvim_buf_set_name(0, "/tmp/dotfiles-visible-other-buffer.lua")
vim.api.nvim_set_current_tabpage(diffview_tab)
assert(commands.should_confirm_quit_all(), "a visible buffer outside Diffview must retain quit-all confirmation")
package.loaded["diffview.lib"] = original_diffview_lib

print("quit-all confirmation regression: ok")
