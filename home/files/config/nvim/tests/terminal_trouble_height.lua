local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
vim.opt.runtimepath:prepend(nvim_root)
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")

vim.o.lines = tonumber(vim.env.NVIM_TEST_LINES) or 47
vim.o.columns = 160

local function open_terminal(_, opts)
	local terminal = {
		buf = vim.api.nvim_create_buf(false, true),
		opts = opts.win,
	}
	vim.bo[terminal.buf].filetype = "snacks_terminal"

	function terminal:valid()
		return self.win and vim.api.nvim_win_is_valid(self.win)
	end

	function terminal:show()
		vim.cmd("botright new")
		self.win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(self.win, self.buf)
		vim.api.nvim_win_set_height(self.win, self.opts.height or 15)
		vim.wo[self.win].winfixheight = true
	end

	function terminal:hide()
		vim.api.nvim_win_close(self.win, true)
		self.win = nil
	end

	function terminal:focus()
		vim.api.nvim_set_current_win(self.win)
	end

	terminal:show()
	return terminal
end

_G.Snacks = { terminal = { open = open_terminal } }
package.loaded["config.tab_pill"] = { set_terminal_highlights = function() end }

vim.cmd("enew")
local editor = vim.api.nvim_get_current_win()
vim.cmd("botright 10new")
local trouble = vim.api.nvim_get_current_win()
vim.bo.filetype = "trouble"
vim.api.nvim_set_current_win(editor)
assert(vim.api.nvim_win_get_height(trouble) == 10, "Trouble must start at ten rows")

local terminal = require("config.terminal")
terminal.setup()
terminal.new()

assert(vim.api.nvim_win_get_height(trouble) == 10, "opening a terminal must preserve Trouble at ten rows")
local terminal_win
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
	if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "snacks_terminal" then
		terminal_win = win
		break
	end
end
assert(terminal_win and vim.api.nvim_win_get_height(terminal_win) == 15, "terminal must retain its configured height")

terminal.toggle()
assert(vim.api.nvim_win_get_height(trouble) == 10, "closing a terminal must restore Trouble to ten rows")

print("terminal Trouble height regression: ok")
