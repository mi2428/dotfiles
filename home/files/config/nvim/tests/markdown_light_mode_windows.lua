local function wait_for(predicate)
	assert(vim.wait(5000, predicate, 20), "timed out waiting for bigfile window setup")
end

local path = vim.fn.tempname() .. ".md"
local lines = {}
for _ = 1, 700 do
	lines[#lines + 1] = string.rep("x", 100)
end
vim.fn.writefile(lines, path)
vim.cmd.edit({ args = { path }, mods = { silent = true } })
wait_for(function()
	return vim.bo.filetype == "bigfile"
end)
local big_win = vim.api.nvim_get_current_win()
local small_buf = vim.api.nvim_create_buf(true, false)
vim.bo[small_buf].filetype = "markdown"
local small_win = vim.api.nvim_open_win(small_buf, true, { split = "below" })
vim.cmd("setlocal cursorline wrap")
vim.api.nvim_set_current_win(big_win)
vim.cmd("split")
local new_big_win = vim.api.nvim_get_current_win()
assert(vim.bo.filetype == "bigfile", "split must retain bigfile buffer")
assert(
	vim.wo[new_big_win].cursorline
		and vim.wo[new_big_win].relativenumber
		and vim.wo[new_big_win].statuscolumn == vim.go.statuscolumn
		and not vim.wo[new_big_win].wrap,
	"split bigfile guards missing"
)
vim.api.nvim_set_current_win(small_win)
assert(vim.bo.filetype == "markdown", "small Markdown peer changed filetype")
assert(vim.wo[small_win].wrap == true, "small peer window options were changed")
local mini_map = require("mini.map")
assert(
	vim.wait(5000, function()
		local native = mini_map.current.win_data[vim.api.nvim_get_current_tabpage()]
		return mini_map.current.buf_data.source == small_buf and native and vim.api.nvim_win_is_valid(native)
	end, 20),
	"mini.map did not select the normal peer"
)
vim.api.nvim_set_current_win(new_big_win)
assert(
	vim.wait(1000, function()
		local native = mini_map.current.win_data[vim.api.nvim_get_current_tabpage()]
		return mini_map.current.buf_data.source == vim.api.nvim_win_get_buf(new_big_win)
			and native
			and vim.api.nvim_win_is_valid(native)
	end, 20),
	"Markdown light-mode window did not become the mini.map source"
)
print("markdown light mode windows: ok")
