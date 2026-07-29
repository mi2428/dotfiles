local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
local mini_map_root = vim.fs.joinpath(vim.fn.stdpath("data"), "lazy/mini.map")
vim.opt.runtimepath:prepend(nvim_root)
vim.opt.runtimepath:prepend(mini_map_root)
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	vim.fs.joinpath(mini_map_root, "lua/?.lua"),
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

local function wait_for(predicate, message)
	assert(vim.wait(2000, predicate, 10), message)
end

local specs = dofile(vim.fs.joinpath(nvim_root, "lua/plugins/minimap.lua"))
local setup_code_layout = upvalue(specs[1].config, "setup_code_layout")
local map = require("mini.map")

vim.o.columns = 120
vim.o.lines = 40
vim.o.laststatus = 0
vim.o.showtabline = 0
vim.wo.breakindent = true
vim.wo.foldcolumn = "0"
vim.wo.number = false
vim.wo.relativenumber = false
vim.wo.signcolumn = "no"
vim.wo.statuscolumn = ""
vim.wo.wrap = true

local source = vim.api.nvim_get_current_win()
local initial_info = assert(vim.fn.getwininfo(source)[1])
local configured_map_width = 12
local initial_text_width = initial_info.width - initial_info.textoff
local initial_usable_width = initial_text_width - configured_map_width
local line = string.rep("x", (3 * initial_usable_width) + initial_text_width)
vim.api.nvim_buf_set_lines(0, 0, -1, false, { line, "after" })
map.setup({
	integrations = {},
	symbols = { encode = map.gen_encode_symbols.dot("4x2") },
	window = { focusable = false, show_integration_count = false, width = 12, winblend = 0, zindex = 30 },
})
setup_code_layout(map)
map.open()

local manager = map._dotfiles_multi_window_manager
local tabpage = vim.api.nvim_get_current_tabpage()
wait_for(function()
	local map_win = map.current.win_data[tabpage]
	return map_win and vim.api.nvim_win_is_valid(map_win) and manager.rendered_maps[map_win]
end, "minimap did not initialize")
local map_win = map.current.win_data[tabpage]
local map_buf = vim.api.nvim_win_get_buf(map_win)
vim.api.nvim_buf_clear_namespace(map_buf, -1, 0, -1)
vim.api.nvim_buf_set_lines(map_buf, 0, -1, false, { "map-1", "map-2", "map-3" })
manager.schedule({ wrap = true, display = true })

local function wrap_marks(win)
	local state = manager.wrap_margins[win]
	if not state then
		return {}
	end
	return vim.api.nvim_buf_get_extmarks(vim.api.nvim_win_get_buf(win), state.namespace, 0, -1, { details = true })
end

wait_for(function()
	local display = manager.rendered_maps[map_win]
	return display
		and vim.api.nvim_win_get_height(display.win) == 3
		and manager.wrap_margins[source]
		and #wrap_marks(source) == 3
end, "wrapped source did not reserve each encoded minimap row")

local info = assert(vim.fn.getwininfo(source)[1])
local text_width = info.width - info.textoff
local map_width = vim.api.nvim_win_get_width(map_win)
local usable_width = text_width - map_width
assert(
	text_width == initial_text_width and usable_width == initial_usable_width,
	("fixture source width changed (width=%s textoff=%s text=%s usable=%s)"):format(
		info.width,
		info.textoff,
		text_width,
		usable_width
	)
)
local marks = wrap_marks(source)
for index, mark in ipairs(marks) do
	assert(mark[2] == 0, "wrap padding escaped the first logical line")
	assert(mark[3] == usable_width * index, "wrap padding is at the wrong source column")
	assert(mark[4].virt_text[1][1] == string.rep(" ", map_width), "wrap padding width does not match minimap")
end

local function cursor_screen_position(win, column)
	vim.api.nvim_win_set_cursor(win, { 1, column - 1 })
	vim.cmd.redraw()
	local position = vim.api.nvim_win_call(win, function()
		return { vim.fn.winline(), vim.fn.wincol() }
	end)
	return position[1], position[2]
end

for index = 1, 3 do
	local last_row, last_col = cursor_screen_position(source, usable_width * index)
	assert(
		last_row == index and last_col == usable_width,
		("source tail did not stop at minimap rail (segment=%s got=%s:%s expected=%s:%s)"):format(
			index,
			last_row,
			last_col,
			index,
			usable_width
		)
	)
	local next_row, next_col = cursor_screen_position(source, usable_width * index + 1)
	assert(next_row == index + 1 and next_col == 1, "source did not wrap immediately after minimap rail")
end
local eof_row, eof_col = cursor_screen_position(source, #line)
assert(eof_row == 4 and eof_col == text_width, "row below encoded minimap EOF did not reclaim pane width")

vim.api.nvim_buf_set_lines(map_buf, 2, -1, false, {})
manager.schedule({ wrap = true, display = true })
wait_for(function()
	local display = manager.rendered_maps[map_win]
	return display and vim.api.nvim_win_get_height(display.win) == 2 and #wrap_marks(source) == 2
end, "shortening minimap did not release its final wrap row")
local shortened_row, shortened_col = cursor_screen_position(source, (2 * usable_width) + text_width)
assert(shortened_row == 3 and shortened_col == text_width, "new row below minimap EOF did not reclaim pane width")
vim.api.nvim_buf_set_lines(map_buf, 2, -1, false, { "map-3" })
manager.schedule({ wrap = true, display = true })
wait_for(function()
	local display = manager.rendered_maps[map_win]
	return display and vim.api.nvim_win_get_height(display.win) == 3 and #wrap_marks(source) == 3
end, "restoring minimap height did not restore wrap padding")

vim.wo[source].wrap = false
vim.api.nvim_exec_autocmds("OptionSet", {
	group = "dotfiles-mini-map-code-layout",
	pattern = "wrap",
	modeline = false,
})
wait_for(function()
	return manager.wrap_margins[source] == nil
end, "disabling wrap did not clear inline padding")
vim.wo[source].wrap = true
vim.api.nvim_exec_autocmds("OptionSet", {
	group = "dotfiles-mini-map-code-layout",
	pattern = "wrap",
	modeline = false,
})
wait_for(function()
	return manager.wrap_margins[source] and #wrap_marks(source) == 3
end, "re-enabling wrap did not restore inline padding")

vim.wo[source].foldcolumn = "1"
vim.wo[source].number = true
vim.wo[source].relativenumber = true
vim.wo[source].signcolumn = "yes:1"
vim.wo[source].statuscolumn = "%l "
manager.schedule({ wrap = true })
wait_for(function()
	local gutter_info = vim.fn.getwininfo(source)[1]
	local current = wrap_marks(source)
	return gutter_info
		and gutter_info.textoff > 0
		and #current > 0
		and current[1][3] == gutter_info.width - gutter_info.textoff - map_width
end, "status, sign, and fold gutters were not subtracted from wrap width")

vim.wo[source].foldcolumn = "0"
vim.wo[source].number = false
vim.wo[source].relativenumber = false
vim.wo[source].signcolumn = "no"
vim.wo[source].statuscolumn = ""
vim.wo[source].list = true
vim.wo[source].listchars = "tab:»·,eol:↵"
vim.cmd.redraw()
local indent_line = "    " .. string.rep("i", text_width * 3)
vim.api.nvim_buf_set_lines(0, 0, -1, false, { indent_line })
manager.schedule({ wrap = true })
wait_for(function()
	local current = wrap_marks(source)
	return #current >= 2 and current[1][3] > 0
end, "breakindent fixture did not create multiple protected rows")
local indent_marks = wrap_marks(source)
assert(
	indent_marks[1][3] == usable_width,
	("first breakindent row used the wrong wrap width (mark=%s expected=%s textoff=%s)"):format(
		indent_marks[1][3],
		usable_width,
		vim.fn.getwininfo(source)[1].textoff
	)
)
assert(
	indent_marks[2][3] == (2 * usable_width) - 4,
	"continuation breakindent was not included in wrap padding position"
)

vim.wo[source].showbreak = "↪ "
assert(manager.wrap_margins[source] == nil, "showbreak did not synchronously clear unsafe padding")
vim.wo[source].showbreak = ""
wait_for(function()
	return manager.wrap_margins[source] and #wrap_marks(source) >= 2
end, "clearing showbreak did not restore wrap padding")
vim.wo[source].linebreak = true
assert(manager.wrap_margins[source] == nil, "linebreak did not synchronously clear unsafe padding")
vim.wo[source].linebreak = false
wait_for(function()
	return manager.wrap_margins[source] and #wrap_marks(source) >= 2
end, "disabling linebreak did not restore wrap padding")

local tab_wide_line = string.rep("a", usable_width - 3) .. "\t界" .. string.rep("z", text_width)
vim.api.nvim_buf_set_lines(0, 0, -1, false, { tab_wide_line })
manager.schedule({ wrap = true })
wait_for(function()
	local current = wrap_marks(source)
	return #current >= 1 and current[1][3] == usable_width - 3
end, "a tab crossing the rail was not moved as one display unit")
local tab_row, tab_col = cursor_screen_position(source, usable_width - 2)
assert(
	tab_row == 2 and tab_col <= vim.bo.tabstop,
	("tab crossing the rail remained under the minimap (got=%s:%s)"):format(tab_row, tab_col)
)
local wide_byte = tab_wide_line:find("界", 1, true)
local wide_row, wide_col = cursor_screen_position(source, wide_byte)
assert(wide_row >= 2 and wide_col <= usable_width, "wide glyph remained under the minimap")

vim.api.nvim_buf_set_lines(0, 0, -1, false, { line })
vim.api.nvim_win_set_cursor(source, { 1, 0 })
vim.api.nvim_win_call(source, function()
	vim.fn.winrestview({ topline = 1, skipcol = 0 })
end)
manager.schedule({ wrap = true })
vim.cmd.vsplit()
local second = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_width(second, 40)
vim.api.nvim_exec_autocmds("WinResized", { group = "dotfiles-mini-map-code-layout", modeline = false })
wait_for(function()
	return manager.wrap_margins[source]
		and manager.wrap_margins[second]
		and #wrap_marks(source) > 0
		and #wrap_marks(second) > 0
end, "split windows did not receive independent wrap padding")
local first_mark = wrap_marks(source)[1]
local second_mark = wrap_marks(second)[1]
local first_info = assert(vim.fn.getwininfo(source)[1])
local second_info = assert(vim.fn.getwininfo(second)[1])
assert(
	first_mark[3] == first_info.width - first_info.textoff - map_width,
	"first split wrap padding ignored its own width"
)
assert(
	second_mark[3] == second_info.width - second_info.textoff - map_width,
	"second split wrap padding ignored its own width"
)
assert(first_mark[3] ~= second_mark[3], "same-buffer split namespaces shared one wrap width")

local namespaces = {}
for win, state in pairs(manager.wrap_margins) do
	namespaces[#namespaces + 1] = { buf = state.buf, namespace = state.namespace, win = win }
end
map.close()
wait_for(function()
	return next(manager.wrap_margins) == nil
end, "closing minimap leaked wrap margin state")
for _, state in ipairs(namespaces) do
	if vim.api.nvim_buf_is_valid(state.buf) then
		assert(
			#vim.api.nvim_buf_get_extmarks(state.buf, state.namespace, 0, -1, {}) == 0,
			"closing minimap leaked inline padding"
		)
	end
end
wait_for(function()
	return not manager.scheduled and next(manager.pending) == nil
end, "scheduled wrap work remained after minimap close")
vim.wait(20, function()
	return false
end)

print("minimap wrap margin regression: ok")
