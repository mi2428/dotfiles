local function wait_for(predicate)
	assert(vim.wait(5000, predicate, 20), "timed out waiting for filetype setup")
end

local function temp_file(suffix, lines)
	local base = vim.fn.tempname()
	local directory = vim.fs.dirname(base)
	local path = vim.fs.joinpath(vim.uv.fs_realpath(directory) or directory, vim.fs.basename(base) .. suffix)
	vim.fn.writefile(lines, path)
	return path
end

local small = temp_file(".md", { "# small", "text" })
vim.cmd.edit({ args = { small }, mods = { silent = true } })
wait_for(function()
	return vim.bo.filetype == "markdown"
end)
assert(vim.bo.filetype == "markdown", "small Markdown must remain markdown")
assert(vim.b.dotfiles_markdown_light_mode ~= true, "small Markdown entered light mode")
local small_buf = vim.api.nvim_get_current_buf()
local render_manager = require("render-markdown.core.manager")
assert(
	vim.wait(5000, function()
		return render_manager.attached(small_buf) == true
	end, 20),
	"render-markdown did not attach to small Markdown"
)
local mini_map = require("mini.map")
assert(
	vim.wait(5000, function()
		return mini_map.current and mini_map.current.buf_data.source == small_buf
	end, 20),
	"mini.map did not use the small Markdown source"
)

local large_lines = {}
for index = 1, 5000 do
	large_lines[#large_lines + 1] = ("## Section %d with **highlighted text**"):format(index)
end
local large = temp_file(".md", large_lines)
vim.cmd.edit({ args = { large }, mods = { silent = true } })
wait_for(function()
	return vim.bo.filetype == "bigfile"
end)
local large_buf = vim.api.nvim_get_current_buf()
assert(vim.bo.filetype == "bigfile", "large Markdown must become bigfile")
assert(vim.b.dotfiles_markdown_light_mode == true, "Markdown light-mode marker missing")
assert(vim.b.dotfiles_bigfile_original_filetype == "markdown", "original filetype marker missing")
assert(vim.b.completion == false and vim.bo.swapfile == false, "buffer guards missing")
assert(
	vim.wait(5000, function()
		local native = mini_map.current.win_data[vim.api.nvim_get_current_tabpage()]
		return mini_map.current.buf_data.source == large_buf and native and vim.api.nvim_win_is_valid(native)
	end, 20),
	"mini.map did not use the Markdown light-mode source"
)
assert(
	vim.wait(5000, function()
		return vim.wo.cursorline
			and vim.wo.winhighlight:find("CursorLine:DotfilesCursorLine", 1, true)
			and vim.wo.winhighlight:find("CursorLineNr:DotfilesCursorLineNr", 1, true)
	end, 20),
	"Markdown light mode did not enable the custom cursorline colors"
)
assert(vim.wo.relativenumber and not vim.wo.wrap, "Markdown relative-number/window guards missing")
assert(vim.wo.statuscolumn == vim.go.statuscolumn and vim.wo.statuscolumn ~= "", "custom statuscolumn missing")
vim.api.nvim_win_set_cursor(0, { 2500, 0 })
vim.cmd.redrawstatus()
local above = vim.api.nvim_eval_statusline(vim.wo.statuscolumn, {
	maxwidth = 20,
	use_statuscol_lnum = 2499,
	winid = vim.api.nvim_get_current_win(),
}).str
local below = vim.api.nvim_eval_statusline(vim.wo.statuscolumn, {
	maxwidth = 20,
	use_statuscol_lnum = 2501,
	winid = vim.api.nvim_get_current_win(),
}).str
assert(above:find("󰄿", 1, true), "line above the cursor did not render the upper marker")
assert(below:find("󰄼", 1, true), "line below the cursor did not render the lower marker")
vim.api.nvim_exec_autocmds("InsertEnter", { modeline = false })
assert(not vim.wo.relativenumber, "InsertEnter did not disable relative numbers")
vim.api.nvim_exec_autocmds("InsertLeave", { modeline = false })
assert(vim.wo.relativenumber, "InsertLeave did not restore Markdown light-mode relative numbers")
assert(
	vim.wait(5000, function()
		local active = vim.treesitter.highlighter and vim.treesitter.highlighter.active
		return active and active[vim.api.nvim_get_current_buf()] ~= nil
	end, 20),
	"Tree-sitter Markdown highlighter did not attach to bigfile"
)
assert(
	vim.wait(1000, function()
		return render_manager.attached(vim.api.nvim_get_current_buf()) ~= true
	end, 20),
	"render-markdown attached to bigfile"
)

vim.cmd.buffer(small_buf)
wait_for(function()
	local native = mini_map.current.win_data[vim.api.nvim_get_current_tabpage()]
	return mini_map.current.buf_data.source == small_buf and native and vim.api.nvim_win_is_valid(native)
end)
vim.cmd.buffer(large_buf)
wait_for(function()
	local native = mini_map.current.win_data[vim.api.nvim_get_current_tabpage()]
	return vim.bo.filetype == "bigfile"
		and mini_map.current.buf_data.source == large_buf
		and native
		and vim.api.nvim_win_is_valid(native)
end)

local lua_lines = {}
for _ = 1, 790 do
	lua_lines[#lua_lines + 1] = string.rep("x", 100)
end
local lua_path = temp_file(".lua", lua_lines)
vim.cmd.edit({ args = { lua_path }, mods = { silent = true } })
wait_for(function()
	return vim.bo.filetype == "lua"
end)
assert(vim.bo.filetype == "lua", "large Lua must not use Markdown threshold")
local lua_buf = vim.api.nvim_get_current_buf()
assert(
	vim.wait(5000, function()
		local native = mini_map.current.win_data[vim.api.nvim_get_current_tabpage()]
		return mini_map.current.buf_data.source == lua_buf and native and vim.api.nvim_win_is_valid(native)
	end, 20),
	"mini.map did not recover after leaving bigfile"
)

local huge_lua_lines = {}
for _ = 1, 16000 do
	huge_lua_lines[#huge_lua_lines + 1] = "-- " .. string.rep("x", 100)
end
local huge_lua_path = temp_file(".lua", huge_lua_lines)
vim.cmd.edit({ args = { huge_lua_path }, mods = { silent = true } })
wait_for(function()
	return vim.bo.filetype == "bigfile"
end)
local huge_lua_buf = vim.api.nvim_get_current_buf()
assert(vim.b.dotfiles_markdown_light_mode ~= true, "generic bigfile entered Markdown light mode")
assert(vim.b.dotfiles_bigfile_original_filetype == "lua", "generic bigfile lost its original filetype")
assert(
	vim.wait(5000, function()
		local native = mini_map.current.win_data[vim.api.nvim_get_current_tabpage()]
		return mini_map.current.buf_data.source == huge_lua_buf and native and vim.api.nvim_win_is_valid(native)
	end, 20),
	"mini.map did not use the generic bigfile source"
)
assert(
	vim.wo.cursorline
		and vim.wo.relativenumber
		and vim.wo.statuscolumn == vim.go.statuscolumn
		and vim.wo.statuscolumn ~= "",
	"generic bigfile did not enable cursorline and relative-number UI"
)
assert(
	vim.wait(5000, function()
		local active = vim.treesitter.highlighter and vim.treesitter.highlighter.active
		return active and active[huge_lua_buf] ~= nil
	end, 20),
	"Tree-sitter Lua highlighter did not attach to generic bigfile"
)

local normal_after_bigfile = temp_file(".lua", { "return true" })
vim.cmd.edit({ args = { normal_after_bigfile }, mods = { silent = true } })
wait_for(function()
	local native = mini_map.current.win_data[vim.api.nvim_get_current_tabpage()]
	return mini_map.current.buf_data.source == vim.api.nvim_get_current_buf()
		and native
		and vim.api.nvim_win_is_valid(native)
end)
mini_map.close()
local normal_after_user_close = temp_file(".lua", { "return false" })
vim.cmd.edit({ args = { normal_after_user_close }, mods = { silent = true } })
vim.wait(300)
local native_after_user_close = mini_map.current.win_data[vim.api.nvim_get_current_tabpage()]
assert(
	not native_after_user_close or not vim.api.nvim_win_is_valid(native_after_user_close),
	"mini.map reopened after an explicit user close"
)

print("markdown light mode: ok")
