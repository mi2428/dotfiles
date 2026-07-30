local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
vim.opt.runtimepath:prepend(nvim_root)
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")

vim.env.XDG_CONFIG_HOME = "/tmp/dotfiles-lazygit-test"
vim.env.LG_CONFIG_FILE = "/tmp/lazygit-base.yml"

local calls = {}
local existing
local fake_terminal = { opts = {}, win = nil }

function fake_terminal:valid()
	return self.win ~= nil and vim.api.nvim_win_is_valid(self.win)
end

function fake_terminal:hide()
	calls.hide = (calls.hide or 0) + 1
	if self:valid() then
		vim.api.nvim_win_close(self.win, true)
	end
	self.win = nil
end

function fake_terminal:show()
	calls.show = (calls.show or 0) + 1
	local parent = self.opts.win
	if parent and vim.api.nvim_win_is_valid(parent) then
		vim.api.nvim_set_current_win(parent)
	end
	vim.cmd(self.opts.position == "top" and "aboveleft new" or "botright new")
	self.win = vim.api.nvim_get_current_win()
end

function fake_terminal:focus()
	calls.focus = (calls.focus or 0) + 1
	vim.api.nvim_set_current_win(self.win)
end

package.loaded.snacks = {
	terminal = {
		get = function(cmd, opts)
			calls.get = { cmd = cmd, opts = opts }
			return existing
		end,
		open = function(cmd, opts)
			calls.open = { cmd = cmd, opts = opts }
			fake_terminal.opts = opts.win
			fake_terminal:show()
			existing = fake_terminal
			return fake_terminal
		end,
	},
}

vim.cmd("enew")
local editor = vim.api.nvim_get_current_win()
local lazygit = require("config.lazygit")
local terminal = lazygit.toggle()

assert(terminal == fake_terminal, "toggle must return the lazygit terminal")
assert(vim.deep_equal(calls.open.cmd, { "lazygit" }), "lazygit command is incorrect")
assert(calls.open.opts.win.position == "bottom", "lazygit must initially open at the bottom")
assert(calls.open.opts.win.relative == "editor", "lazygit must initially span the editor")
assert(calls.open.opts.win.height == 15, "lazygit must use its fixed height")
assert(calls.open.opts.win.stack == false, "lazygit must remain independent from stacked terminals")
assert(calls.open.opts.win.wo.winfixheight == true, "lazygit height must remain fixed")
assert(vim.api.nvim_win_get_height(fake_terminal.win) == 15, "lazygit must enforce its initial text height")
for direction, name in pairs({ h = "left", j = "lower", k = "upper", l = "right" }) do
	local mapping = assert(calls.open.opts.win.keys["pane_" .. name], "lazygit pane mapping is missing")
	assert(mapping[1] == "<C-w>" .. direction, "lazygit pane mapping has the wrong key")
	assert(type(mapping[2]) == "function", "lazygit pane mapping must use a callback")
	assert(mapping.mode == "t", "lazygit pane mapping must work directly in terminal mode")
	assert(mapping.nowait == true, "lazygit pane mapping must not wait after the direction key")
end
assert(
	calls.open.opts.env.LG_CONFIG_FILE == "/tmp/lazygit-base.yml,/tmp/dotfiles-lazygit-test/herdr/lazygit-unified.yml",
	"lazygit must use the compact unified layout config"
)

local lazygit_win = fake_terminal.win
calls.open.opts.win.keys.pane_upper[2]()
assert(vim.api.nvim_get_current_win() == editor, "<C-w>k must move directly from lazygit to the editor")
vim.api.nvim_set_current_win(lazygit_win)
calls.open.opts.win.keys.pane_lower[2]()
assert(vim.api.nvim_get_current_win() == lazygit_win, "a missing pane must leave lazygit focused")

lazygit.toggle()
assert(calls.hide == 1, "a visible lazygit pane must be hidden")

vim.api.nvim_set_current_win(editor)
vim.cmd("botright 10new")
local shell_win = vim.api.nvim_get_current_win()
vim.w[shell_win].dotfiles_terminal_group = 1
vim.api.nvim_set_current_win(editor)

lazygit.toggle()
assert(fake_terminal.opts.position == "top", "lazygit must open above an existing terminal pane")
assert(fake_terminal.opts.relative == "win", "lazygit must be placed relative to the existing terminal")
assert(fake_terminal.opts.win == shell_win, "lazygit must use the existing terminal as its split anchor")
assert(calls.show == 2, "a hidden lazygit terminal must be shown again")
assert(calls.focus == 1, "a reopened lazygit terminal must receive focus")
assert(vim.api.nvim_win_get_height(fake_terminal.win) == 15, "lazygit must enforce its reopened text height")

print("lazygit pane regression: ok")
