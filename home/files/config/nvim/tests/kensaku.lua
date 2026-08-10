local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local dictionary = assert(vim.env.KENSAKU_TEST_DICT, "KENSAKU_TEST_DICT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")

local kensaku = dofile(vim.fs.joinpath(nvim_root, "lua/config/kensaku.lua"))
kensaku.setup({ dictionary = dictionary })
assert(vim.fn.exists(":Kensaku") == 2, ":Kensaku was not defined")

vim.api.nvim_buf_set_lines(0, 0, -1, false, { "English", "日本語 one", "middle", "日本語 two" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.v.searchforward = 0
vim.cmd.nohlsearch()
vim.cmd("Kensaku nihongo")
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 2, 0 }), "Kensaku moved to the wrong position")
assert(vim.regex(vim.fn.getreg("/")):match_str("日本語") ~= nil, "Kensaku did not set a reusable search pattern")
assert(vim.v.searchforward == 1, "Kensaku did not set forward search direction")
assert(vim.v.hlsearch == 1, "Kensaku did not enable search highlighting")

vim.cmd.normal({ args = { "n" }, bang = true })
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 4, 0 }), "n did not reach the next Migemo match")
vim.cmd.normal({ args = { "N" }, bang = true })
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 2, 0 }), "N did not reach the previous Migemo match")

print("Kensaku Migemo search: ok")
