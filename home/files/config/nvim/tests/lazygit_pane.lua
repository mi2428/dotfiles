local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
vim.opt.runtimepath:prepend(nvim_root)
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")

vim.o.lines = 60
vim.o.columns = 180
vim.env.XDG_CONFIG_HOME = "/tmp/dotfiles-lazygit-test"
vim.env.LG_CONFIG_FILE = "/tmp/lazygit-base.yml"

local calls = { open = {}, show = 0, hide = 0, close = 0, focus = 0 }

local function fake_terminal(opts)
	local terminal = {
		buf = vim.api.nvim_create_buf(false, true),
		opts = opts.win,
	}
	vim.bo[terminal.buf].filetype = "snacks_terminal"

	function terminal:valid()
		return self.win ~= nil
			and vim.api.nvim_win_is_valid(self.win)
			and vim.api.nvim_win_get_buf(self.win) == self.buf
	end

	function terminal:show()
		calls.show = calls.show + 1
		local parent = self.opts.win
		if parent and vim.api.nvim_win_is_valid(parent) then
			vim.api.nvim_set_current_win(parent)
		end

		if self.opts.position == "right" then
			local total_width = vim.api.nvim_win_get_width(vim.api.nvim_get_current_win())
			vim.cmd("rightbelow vsplit")
			vim.api.nvim_win_set_width(0, math.floor(total_width * (self.opts.width or 0.5)))
		elseif self.opts.position == "top" then
			vim.cmd("aboveleft new")
		else
			vim.cmd("botright new")
		end

		self.win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(self.win, self.buf)
		if self.opts.height then
			vim.api.nvim_win_set_height(self.win, self.opts.height)
		end
		vim.wo[self.win].winfixheight = self.opts.wo.winfixheight
	end

	function terminal:hide()
		calls.hide = calls.hide + 1
		if self:valid() then
			vim.api.nvim_win_close(self.win, true)
		end
		self.win = nil
	end

	function terminal:close()
		calls.close = calls.close + 1
		self:hide()
		if vim.api.nvim_buf_is_valid(self.buf) then
			vim.api.nvim_buf_delete(self.buf, { force = true })
		end
	end

	function terminal:focus()
		calls.focus = calls.focus + 1
		vim.api.nvim_set_current_win(self.win)
	end

	terminal:show()
	return terminal
end

package.loaded.snacks = {
	terminal = {
		open = function(cmd, opts)
			local terminal = fake_terminal(opts)
			calls.open[#calls.open + 1] = { cmd = cmd, opts = opts, terminal = terminal }
			return terminal
		end,
	},
}

local function assert_ratio(group)
	local files_width = vim.api.nvim_win_get_width(group.files.win)
	local commits_width = vim.api.nvim_win_get_width(group.commits.win)
	local ratio = commits_width / (files_width + commits_width)
	assert(math.abs(ratio - 0.7) < 0.02, ("lazygit pane ratio must be 7:3, got %.3f"):format(ratio))
end

local function assert_pane_keys(opts)
	for direction, name in pairs({ h = "left", j = "lower", k = "upper", l = "right" }) do
		local mapping = assert(opts.win.keys["pane_" .. name], "lazygit pane mapping is missing")
		assert(mapping[1] == "<C-w>" .. direction, "lazygit pane mapping has the wrong key")
		assert(type(mapping[2]) == "function", "lazygit pane mapping must use a callback")
		assert(mapping.mode == "t", "lazygit pane mapping must work directly in terminal mode")
		assert(mapping.nowait == true, "lazygit pane mapping must not wait after the direction key")
	end
end

vim.cmd("enew")
local editor = vim.api.nvim_get_current_win()
local lazygit = require("config.lazygit")
local group = lazygit.toggle()

assert(#calls.open == 2, "lazygit workspace must open two terminals")
assert(
	vim.deep_equal(calls.open[1].cmd, { "lazygit", "log", "--screen-mode", "full" }),
	"left pane must open the full-screen Commits view"
)
assert(
	vim.deep_equal(calls.open[2].cmd, { "lazygit", "status", "--screen-mode", "full" }),
	"right pane must open the full-screen Files view"
)
assert(calls.open[1].opts.win.position == "bottom", "Commits must initially open at the bottom")
assert(calls.open[2].opts.win.position == "right", "Files must open to the right of Commits")
assert(calls.open[2].opts.win.win == group.commits.win, "Files must be anchored to Commits")
assert(math.abs(calls.open[2].opts.win.width - 0.3) < 0.001, "Files must request thirty percent width")
assert(calls.open[1].opts.win.wo.winbar:find("Commits", 1, true), "left winbar must identify Commits")
assert(calls.open[2].opts.win.wo.winbar:find("Files", 1, true), "right winbar must identify Files")
assert(vim.api.nvim_win_get_height(group.files.win) == 15, "Files height must be fixed")
assert(vim.api.nvim_win_get_height(group.commits.win) == 15, "Commits height must be fixed")
assert_ratio(group)
assert_pane_keys(calls.open[1].opts)
assert_pane_keys(calls.open[2].opts)
assert(calls.open[1].opts.env.LG_CONFIG_FILE == table.concat({
	"/tmp/lazygit-base.yml",
	"/tmp/dotfiles-lazygit-test/herdr/lazygit-unified.yml",
	"/tmp/dotfiles-lazygit-test/lazygit/nvim-files-commits.yml",
}, ","), "Commits must add the whole-graph config")
assert(
	calls.open[2].opts.env.LG_CONFIG_FILE
		== "/tmp/lazygit-base.yml,/tmp/dotfiles-lazygit-test/herdr/lazygit-unified.yml",
	"Files must use the compact unified config"
)
assert(vim.api.nvim_get_current_win() == group.commits.win, "Commits must receive initial focus")

calls.open[1].opts.win.keys.pane_right[2]()
assert(vim.api.nvim_get_current_win() == group.files.win, "<C-w>l must move from Commits to Files")
calls.open[2].opts.win.keys.pane_left[2]()
assert(vim.api.nvim_get_current_win() == group.commits.win, "<C-w>h must move from Files to Commits")
calls.open[1].opts.win.keys.pane_upper[2]()
assert(vim.api.nvim_get_current_win() == editor, "<C-w>k must move from lazygit to the editor")

lazygit.toggle()
assert(calls.hide == 2, "toggling must hide both lazygit panes")
assert(not group.files:valid() and not group.commits:valid(), "both lazygit panes must be hidden")

vim.api.nvim_set_current_win(editor)
vim.cmd("botright 10new")
local shell_win = vim.api.nvim_get_current_win()
vim.w[shell_win].dotfiles_terminal_group = 1
vim.api.nvim_set_current_win(editor)

group = lazygit.toggle()
assert(group.commits.opts.position == "top", "Commits must reopen above an existing terminal")
assert(group.commits.opts.relative == "win", "Commits must be placed relative to the existing terminal")
assert(group.commits.opts.win == shell_win, "Commits must use the existing terminal as its split anchor")
assert(group.files.opts.position == "right", "Files must remain to the right after reopening")
assert(calls.show == 4, "both hidden lazygit terminals must be shown again")
assert(vim.api.nvim_win_get_height(group.files.win) == 15, "reopened Files height must remain fixed")
assert(vim.api.nvim_win_get_height(group.commits.win) == 15, "reopened Commits height must remain fixed")
assert_ratio(group)
assert(vim.fn.win_screenpos(shell_win)[1] > vim.fn.win_screenpos(group.files.win)[1], "shell must remain below lazygit")

lazygit.close_all()
assert(calls.close == 2, "closing all must terminate both lazygit processes")
assert(not group.files:valid() and not group.commits:valid(), "closing all must remove both lazygit panes")

print("lazygit pane regression: ok")
