local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
vim.opt.runtimepath:prepend(nvim_root)
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")

local calls = {}
vim.paste = function(lines, phase)
	calls[#calls + 1] = { lines = lines, phase = phase }
	return true
end
local notices = {}
vim.notify = function(message)
	notices[#notices + 1] = message
end

dofile(vim.fs.joinpath(nvim_root, "lua/config/options.lua"))
local guarded_buf = vim.api.nvim_get_current_buf()
local threshold = 64 * 1024

assert(vim.paste({ string.rep("a", threshold) }, -1), "paste wrapper must preserve the original return value")
assert(vim.wo.breakindent, "a line at the threshold must keep breakindent")
assert(not vim.b[guarded_buf].dotfiles_long_line_paste, "a line at the threshold must not mark the buffer")

vim.paste({ string.rep("b", 40 * 1024) }, 1)
assert(vim.wo.breakindent, "the first streamed chunk must not trigger early")
vim.paste({ string.rep("b", 30 * 1024) }, 3)
assert(not vim.wo.breakindent, "streamed chunks from one long line must disable breakindent")
assert(vim.b[guarded_buf].dotfiles_long_line_paste, "the guarded buffer must be marked")
assert(#calls == 3, "the wrapper must forward every paste phase")
assert(vim.wait(100, function()
	return #notices == 1
end), "the guard must notify once")

local plain_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_win_set_buf(0, plain_buf)
assert(vim.wo.breakindent, "leaving a guarded buffer must restore breakindent")
vim.paste({ string.rep("c", 48 * 1024), string.rep("d", 48 * 1024) }, -1)
assert(vim.wo.breakindent, "multiple short lines must keep breakindent")
assert(not vim.b[plain_buf].dotfiles_long_line_paste, "multiple short lines must not mark the buffer")

vim.api.nvim_win_set_buf(0, guarded_buf)
assert(not vim.wo.breakindent, "returning to a guarded buffer must disable breakindent again")

print("long paste guard regression: ok")
