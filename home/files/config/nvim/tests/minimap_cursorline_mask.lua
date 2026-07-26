local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
vim.opt.runtimepath:prepend(nvim_root)
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")

local function upvalue(fn, expected_name)
	for index = 1, math.huge do
		local name, value = debug.getupvalue(fn, index)
		if not name then
			break
		end
		if name == expected_name then
			return value
		end
	end
	error("missing upvalue: " .. expected_name)
end

local specs = dofile(vim.fs.joinpath(nvim_root, "lua/plugins/minimap.lua"))
local setup_cursorline_mask = upvalue(specs[1].config, "setup_cursorline_mask")
local mask_cursorline_rows = upvalue(setup_cursorline_mask, "mask_cursorline_rows")
local win = vim.api.nvim_get_current_win()
local buf = vim.api.nvim_get_current_buf()

local function with_stubs(screenpos, callback)
	local original_screenpos = vim.fn.screenpos
	local original_set_extmark = vim.api.nvim_buf_set_extmark
	local marks = {}

	vim.fn.screenpos = screenpos
	vim.api.nvim_buf_set_extmark = function(_, _, line, column, options)
		marks[#marks + 1] = { line = line, column = column, options = options }
		return #marks
	end

	local ok, result = xpcall(function()
		return callback(marks)
	end, debug.traceback)
	vim.fn.screenpos = original_screenpos
	vim.api.nvim_buf_set_extmark = original_set_extmark
	if not ok then
		error(result, 0)
	end
	return result
end

local function with_wrap(enabled, callback)
	local original_wrap = vim.wo[win].wrap
	vim.wo[win].wrap = enabled
	local ok, result = xpcall(callback, debug.traceback)
	vim.wo[win].wrap = original_wrap
	if not ok then
		error(result, 0)
	end
	return result
end

local function assert_columns(marks, expected, message)
	assert(#marks == #expected, ("%s: got %d marks, expected %d"):format(message, #marks, #expected))
	for index, column in ipairs(expected) do
		assert(marks[index].column == column, ("%s: mark %d got column %d, expected %d"):format(message, index, marks[index].column, column))
	end
end

local function screen_rows(row_for_byte)
	local calls = 0
	return function(_, _, column)
		calls = calls + 1
		return { row = row_for_byte(column - 1) }
	end, function()
		return calls
	end
end

vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "abcdefghij" })
local ascii_screenpos, ascii_calls = screen_rows(function(byte_column)
	return 10 + math.floor(byte_column / 3)
end)
with_wrap(true, function()
	with_stubs(ascii_screenpos, function(marks)
		mask_cursorline_rows(buf, win, { 1, 4 }, 11, 500, 12, 1, 80)
		assert_columns(marks, { 3, 6, 9 }, "ASCII wrapped intersection in a tall MiniMap")
		assert(ascii_calls() <= 20, "wrapped cursor must not search every tall MiniMap row")
	end)
end)

local empty_screenpos, empty_calls = screen_rows(function(byte_column)
	return 10 + math.floor(byte_column / 3)
end)
with_wrap(true, function()
	with_stubs(empty_screenpos, function(marks)
		mask_cursorline_rows(buf, win, { 1, 4 }, 100, 500, 12, 1, 80)
		assert(#marks == 0, "empty vertical intersection must not emit a mask")
		assert(empty_calls() == 3, "empty vertical intersection must avoid find_row searches")
	end)
end)

local utf8 = "a界b界c"
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { utf8 })
local utf8_rows = {
	[0] = 10,
	[1] = 11,
	[4] = 12,
	[5] = 13,
	[8] = 14,
	[9] = 15,
}
local utf8_screenpos, utf8_calls = screen_rows(function(byte_column)
	return assert(utf8_rows[byte_column], "unexpected UTF-8 byte column: " .. byte_column)
end)
with_wrap(true, function()
	with_stubs(utf8_screenpos, function(marks)
		mask_cursorline_rows(buf, win, { 1, 5 }, 11, 14, 12, 1, 80)
		assert_columns(marks, { 1, 4, 5, 8 }, "UTF-8 wrapped intersection")
		assert(utf8_calls() <= 24, "UTF-8 lookup must scale with cursor rows, not MiniMap height")
	end)
end)

with_wrap(false, function()
	with_stubs(function()
		return { row = 12 }
	end, function(marks)
		mask_cursorline_rows(buf, win, { 1, 5 }, 11, 12, 12, 1, 80)
		assert_columns(marks, { 5 }, "nowrap path")
	end)
end)

with_wrap(true, function()
	with_stubs(function()
		error("full-viewport fast path must not call screenpos")
	end, function(marks)
		mask_cursorline_rows(buf, win, { 1, 5 }, 1, 100, 12, 10, 20)
		assert_columns(marks, { 0 }, "full-viewport wrapped fast path")
		assert(marks[1].options.virt_text_repeat_linebreak, "full-viewport path must repeat on wrapped rows")
	end)
end)

print("minimap cursorline mask regression: ok")
