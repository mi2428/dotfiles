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

local specs = dofile(vim.fs.joinpath(nvim_root, "lua/plugins/minimap.lua"))
local setup_code_layout = upvalue(specs[1].config, "setup_code_layout")
local set_minimap_highlights = upvalue(specs[1].config, "set_minimap_highlights")
local map = require("mini.map")

vim.o.columns = 180
vim.o.lines = 52
local source_lines = {}
for line = 1, 5000 do
	source_lines[line] = ("line %04d %s"):format(line, string.rep("x", line % 80))
end
vim.api.nvim_buf_set_lines(0, 0, -1, false, source_lines)

map.setup({
	integrations = {
		map.gen_integration.builtin_search({ search = "Search" }),
		map.gen_integration.diagnostic({ error = "ErrorMsg" }),
	},
	symbols = { encode = map.gen_encode_symbols.dot("4x2") },
	window = {
		focusable = false,
		show_integration_count = false,
		width = 12,
		winblend = 0,
		zindex = 30,
	},
})
set_minimap_highlights()
setup_code_layout(map)
map.open()

local manager = map._dotfiles_multi_window_manager
local function count_mirrors()
	return vim.tbl_count(manager.mirrors)
end

local function wait_for(predicate, message)
	assert(vim.wait(2000, predicate, 10), message)
end

local function assert_map_geometry(source_win)
	local map_win = assert(manager.map_window_for_source(source_win), "source window has no minimap")
	assert(vim.api.nvim_win_is_valid(map_win), "source window minimap is invalid")
	local source_position = vim.api.nvim_win_get_position(source_win)
	local config = vim.api.nvim_win_get_config(map_win)
	assert(config.row == source_position[1], "minimap row does not match its source window")
	assert(
		config.col == source_position[2] + vim.api.nvim_win_get_width(source_win),
		"stateful minimap right edge does not match its source window"
	)
	assert(config.hide, "rectangular stateful minimap window must be hidden")
	assert(config.height == vim.api.nvim_win_get_height(source_win), "minimap height does not match its source window")
	assert(vim.wo[map_win].winblend == 0, "stateful minimap windows must remain opaque when focused")
	assert(
		vim.wo[map_win].winhighlight:find("EndOfBuffer:MiniMapNormal", 1, true),
		"native and mirror minimap filler rows must use the minimap background"
	)
	local rendered_rows = assert(manager.rendered_rows[map_win], "minimap has no cropped display rows")
	assert(vim.tbl_count(rendered_rows) > 0, "minimap has no visible content rows")
	local expected_left = source_position[2] + vim.api.nvim_win_get_width(source_win) - config.width
	for map_line, row in pairs(rendered_rows) do
		assert(vim.api.nvim_win_is_valid(row.win), "cropped minimap row is invalid")
		local row_config = vim.api.nvim_win_get_config(row.win)
		assert(row_config.row == source_position[1] + map_line, "cropped minimap row is vertically misplaced")
		assert(row_config.col == expected_left, "cropped minimap row is horizontally misplaced")
		assert(row_config.height == 1, "cropped minimap row must be one screen row high")
		assert(row_config.width == config.width, "encoded minimap row must cover from rail to pane edge")
		assert(vim.wo[row.win].winblend == 0, "cropped minimap occupied intervals must be opaque")
	end
	return map_win
end

local first = vim.api.nvim_get_current_win()
vim.cmd.vsplit()
local second = vim.api.nvim_get_current_win()
wait_for(function()
	return count_mirrors() == 1
end, "vertical split did not create a second minimap")

vim.w[first].dotfiles_disable_minimap = true
map.refresh({}, { integrations = false, lines = false, scrollbar = false })
wait_for(function()
	return count_mirrors() == 0 and manager.map_window_for_source(first) == nil
end, "a window-local minimap opt-out did not remove the inactive split map")
vim.api.nvim_set_current_win(first)
map.refresh({}, { integrations = false, lines = false, scrollbar = false })
assert(map._dotfiles_source_win == second, "a minimap-disabled split must not take native map ownership")
vim.w[first].dotfiles_disable_minimap = false
vim.api.nvim_set_current_win(second)
map.refresh({}, { integrations = false, lines = false, scrollbar = false })
wait_for(function()
	return count_mirrors() == 1
end, "re-enabling a split minimap did not restore its mirror")

local first_map = assert_map_geometry(first)
local second_map = assert_map_geometry(second)
assert(first_map ~= second_map, "split windows must not share a minimap window")
assert(
	vim.api.nvim_win_get_buf(first_map) ~= vim.api.nvim_win_get_buf(second_map),
	"split windows must use separate minimap buffers for independent scrollbars"
)

vim.api.nvim_win_call(first, function()
	vim.cmd("normal! 20Gzt")
end)
vim.api.nvim_win_call(second, function()
	vim.cmd("normal! 4560Gzt")
end)
vim.api.nvim_set_current_win(second)
map.refresh({}, { integrations = false, lines = false })
wait_for(function()
	local mirror = manager.mirrors[first]
	return mirror and mirror.cursor_line == 20
end, "inactive split scrollbar did not track its own cursor")

local namespaces = vim.api.nvim_get_namespaces()
local mirror_line_namespace = assert(namespaces["dotfiles-mini-map-mirror-scroll-line"])
local native_line_namespace = assert(namespaces.MiniMapScrollLine)
local first_marks = vim.api.nvim_buf_get_extmarks(
	vim.api.nvim_win_get_buf(first_map),
	first == map._dotfiles_source_win and native_line_namespace or mirror_line_namespace,
	0,
	-1,
	{}
)
local second_marks = vim.api.nvim_buf_get_extmarks(
	vim.api.nvim_win_get_buf(second_map),
	second == map._dotfiles_source_win and native_line_namespace or mirror_line_namespace,
	0,
	-1,
	{}
)
assert(#first_marks == 1 and #second_marks == 1, "each minimap must have exactly one cursor marker")
assert(first_marks[1][2] ~= second_marks[1][2], "split minimaps must render independent cursor positions")

vim.fn.setreg("/", "line 0042")
vim.v.hlsearch = 1
map.refresh({}, { integrations = true, lines = false, scrollbar = false })
local native_integration_namespace = assert(namespaces.MiniMapIntegrations)
local mirror_integration_namespace = assert(namespaces["dotfiles-mini-map-mirror-integrations"])
local function integration_count(source_win, map_win)
	local namespace = source_win == map._dotfiles_source_win and native_integration_namespace
		or mirror_integration_namespace
	return #vim.api.nvim_buf_get_extmarks(vim.api.nvim_win_get_buf(map_win), namespace, 0, -1, {})
end
wait_for(function()
	return integration_count(first, first_map) > 0 and integration_count(second, second_map) > 0
end, "search integration was not rendered in every minimap")
require("config.multi_search").setup()
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-l>", true, false, true), "x", false)
wait_for(function()
	return vim.v.hlsearch == 0
		and integration_count(first, first_map) == 0
		and integration_count(second, second_map) == 0
end, "<C-l> search clearing did not clear every minimap")

local reused_mirror_buf = manager.mirrors[first].buf
vim.api.nvim_set_current_win(first)
wait_for(function()
	return manager.mirrors[first] == nil and manager.mirrors[second] ~= nil
end, "native and mirror minimaps did not exchange ownership on focus")
assert(
	manager.mirrors[second].buf == reused_mirror_buf,
	"focus change unnecessarily re-encoded into a new mirror buffer"
)
vim.api.nvim_set_current_win(second)
wait_for(function()
	return manager.mirrors[second] == nil and manager.mirrors[first] ~= nil
end, "returning focus did not restore native and mirror minimap ownership")
assert(manager.mirrors[first].buf == reused_mirror_buf, "returning focus unnecessarily recreated the mirror buffer")

local focused_native = assert(manager.map_window_for_source(second))
map.toggle_focus()
wait_for(function()
	local focused_line = vim.api.nvim_win_get_cursor(focused_native)[1] - 1
	local row = (manager.rendered_rows[focused_native] or {})[focused_line]
	return manager.focused
		and vim.api.nvim_get_current_win() == focused_native
		and vim.api.nvim_win_get_config(focused_native).hide
		and row
		and vim.wo[row.win].cursorline
end, "focused minimap did not retain cropped opaque rows and a visible focus line")
map.toggle_focus(true)
wait_for(function()
	return not manager.focused
		and vim.api.nvim_get_current_win() == second
		and vim.api.nvim_win_get_config(focused_native).hide
		and vim.tbl_count(manager.rendered_rows[focused_native] or {}) > 0
end, "leaving minimap focus did not restore the cropped renderer")

vim.cmd.split()
local third = vim.api.nvim_get_current_win()
wait_for(function()
	return count_mirrors() == 2
end, "horizontal split did not create a minimap for every source window")

local map_windows = {}
for _, win in ipairs({ first, second, third }) do
	local map_win = assert_map_geometry(win)
	assert(not map_windows[map_win], "three source windows must have three distinct minimap windows")
	map_windows[map_win] = true
end

vim.api.nvim_set_current_win(first)
wait_for(function()
	return map._dotfiles_source_win == first
		and count_mirrors() == 2
		and manager.mirrors[first] == nil
		and manager.mirrors[second] ~= nil
		and manager.mirrors[third] ~= nil
		and vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(manager.map_window_for_source(first)))
			== vim.api.nvim_win_get_height(first)
end, "changing split focus did not transfer the native minimap without losing mirrors")
for _, win in ipairs({ first, second, third }) do
	assert_map_geometry(win)
end

local benchmark_cursor = 0
local function benchmark(iterations, callback)
	collectgarbage("collect")
	local started = vim.uv.hrtime()
	for _ = 1, iterations do
		callback()
	end
	return (vim.uv.hrtime() - started) / 1e6 / iterations
end

local function move_in_inactive_split()
	benchmark_cursor = (benchmark_cursor % #source_lines) + 1
	vim.api.nvim_win_set_cursor(second, { benchmark_cursor, 0 })
	manager.refresh_scrollbars()
end

local two_mirror_scroll_ms = benchmark(1000, move_in_inactive_split)
local two_mirror_content_ms = benchmark(20, manager.refresh_content)
local flush = upvalue(manager.schedule, "flush")
local two_mirror_layout_ms = benchmark(100, function()
	manager.pending = { scrollbar = true }
	flush()
end)

vim.api.nvim_win_close(third, true)
wait_for(function()
	return count_mirrors() == 1
end, "closing a source split leaked its mirror minimap")

local one_mirror_scroll_ms = benchmark(1000, move_in_inactive_split)
local one_mirror_content_ms = benchmark(20, manager.refresh_content)
assert(two_mirror_scroll_ms < 1, "two-mirror scrollbar refresh regressed above 1 ms per cursor move")
assert(one_mirror_scroll_ms < 1, "one-mirror scrollbar refresh regressed above 1 ms per cursor move")
assert(two_mirror_content_ms < 100, "two-mirror content refresh regressed above 100 ms")
assert(one_mirror_content_ms < 100, "one-mirror content refresh regressed above 100 ms")
assert(two_mirror_layout_ms < 10, "two-mirror cropped layout refresh regressed above 10 ms")

local other_buf = vim.api.nvim_create_buf(true, false)
local other_lines = {}
for line = 1, 73 do
	other_lines[line] = ("other buffer %03d"):format(line)
end
vim.api.nvim_buf_set_lines(other_buf, 0, -1, false, other_lines)
vim.api.nvim_win_set_buf(second, other_buf)
local diagnostic_namespace = vim.api.nvim_create_namespace("dotfiles-minimap-mixed-buffer-test")
vim.diagnostic.set(diagnostic_namespace, other_buf, {
	{ lnum = 8, col = 0, severity = vim.diagnostic.severity.ERROR, message = "mixed-buffer diagnostic" },
})
map.refresh()
wait_for(function()
	local mirror = manager.mirrors[second]
	return mirror and mirror.encode_data and mirror.encode_data.source_rows == #other_lines
end, "a different-buffer split did not receive its own minimap content")
local mixed_mirror = manager.mirrors[second]
local integration_namespace = assert(vim.api.nvim_get_namespaces()["dotfiles-mini-map-mirror-integrations"])
assert(
	#vim.api.nvim_buf_get_extmarks(mixed_mirror.buf, integration_namespace, 0, -1, {}) == 1,
	"different-buffer minimap integrations used the native map's source buffer"
)
assert_map_geometry(first)
assert_map_geometry(second)

vim.api.nvim_set_current_win(second)
wait_for(function()
	local mirror = manager.mirrors[first]
	return map.current.buf_data.source == other_buf
		and mirror
		and mirror.encode_data
		and mirror.encode_data.source_rows == #source_lines
end, "focusing another buffer did not exchange native and mirror minimaps")
assert_map_geometry(first)
assert_map_geometry(second)
vim.api.nvim_set_current_win(first)
wait_for(function()
	local mirror = manager.mirrors[second]
	return map.current.buf_data.source == vim.api.nvim_win_get_buf(first)
		and mirror
		and mirror.encode_data
		and mirror.encode_data.source_rows == #other_lines
end, "returning focus did not restore different-buffer minimaps")

local toggle_all = specs[1].keys[1][2]
toggle_all()
wait_for(function()
	return count_mirrors() == 0 and map.current.win_data[vim.api.nvim_get_current_tabpage()] == nil
end, "<leader>um did not close every minimap")
toggle_all()
wait_for(function()
	local native = map.current.win_data[vim.api.nvim_get_current_tabpage()]
	local mirror = manager.mirrors[second]
	return native
		and vim.api.nvim_win_is_valid(native)
		and mirror
		and mirror.encode_data
		and mirror.encode_data.source_rows == #other_lines
end, "<leader>um did not reopen a minimap for every code window")

vim.api.nvim_set_current_win(first)
local first_buf = vim.api.nvim_win_get_buf(first)
vim.cmd("botright 5new")
local non_code_win = vim.api.nvim_get_current_win()
vim.bo[vim.api.nvim_get_current_buf()].buftype = "nofile"
toggle_all()
wait_for(function()
	return count_mirrors() == 0 and map.current.win_data[vim.api.nvim_get_current_tabpage()] == nil
end, "non-code <leader>um did not close every minimap")
toggle_all()
local reopened_from_non_code = vim.wait(2000, function()
	local native = map.current.win_data[vim.api.nvim_get_current_tabpage()]
	return vim.api.nvim_get_current_win() == non_code_win
		and map.current.buf_data.source == first_buf
		and native
		and vim.api.nvim_win_is_valid(native)
		and count_mirrors() == 1
end, 10)
assert(
	reopened_from_non_code,
	("non-code toggle state: current=%s expected=%s source=%s expected_source=%s mirrors=%s"):format(
		vim.api.nvim_get_current_win(),
		non_code_win,
		tostring(map.current.buf_data.source),
		first_buf,
		count_mirrors()
	)
)
vim.api.nvim_win_close(non_code_win, true)

-- `:only` closes floating windows without calling MiniMap.close(). The map is
-- still logically enabled and must recover before a subsequent split is made.
vim.cmd.only()
wait_for(function()
	local native = map.current.win_data[vim.api.nvim_get_current_tabpage()]
	return native and vim.api.nvim_win_is_valid(native) and count_mirrors() == 0
end, ":only did not restore the enabled native minimap")
vim.cmd.split()
wait_for(function()
	return count_mirrors() == 1
end, ":split after :only did not create a minimap for both code windows")
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
	if vim.api.nvim_win_get_config(win).relative == "" and vim.bo[vim.api.nvim_win_get_buf(win)].buftype == "" then
		assert_map_geometry(win)
	end
end

local active_empty_source = vim.api.nvim_get_current_win()
vim.api.nvim_buf_set_lines(vim.api.nvim_win_get_buf(active_empty_source), 0, -1, false, { "" })
map.refresh()
wait_for(function()
	local native = manager.map_window_for_source(active_empty_source)
	return native
		and vim.api.nvim_win_is_valid(native)
		and vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(native)) == 1
		and vim.tbl_count(manager.rendered_rows[native] or {}) == 1
end, "an empty source buffer did not retain its visible scrollbar row")
local empty_native = manager.map_window_for_source(active_empty_source)
local empty_line_marks = vim.api.nvim_buf_get_extmarks(
	vim.api.nvim_win_get_buf(empty_native),
	assert(vim.api.nvim_get_namespaces().MiniMapScrollLine),
	0,
	-1,
	{}
)
assert(#empty_line_marks == 1 and empty_line_marks[1][2] == 0, "trimming moved the empty-buffer cursor rail")

vim.cmd("leftabove 8vnew")
local narrow_source = vim.api.nvim_get_current_win()
wait_for(function()
	local narrow_map = manager.map_window_for_source(narrow_source)
	local row = narrow_map and (manager.rendered_rows[narrow_map] or {})[0]
	return narrow_map
		and vim.api.nvim_win_is_valid(narrow_map)
		and vim.api.nvim_win_get_width(narrow_map) == vim.api.nvim_win_get_width(narrow_source)
		and row
		and vim.api.nvim_win_get_config(row.win).col == vim.api.nvim_win_get_position(narrow_source)[2]
		and vim.api.nvim_win_get_width(row.win) == vim.api.nvim_win_get_width(narrow_map)
end, "narrow pane did not re-encode and retain its rail inside the source window")

map.close()
wait_for(function()
	return count_mirrors() == 0
end, "closing mini.map leaked mirror windows")
vim.wait(20, function()
	return false
end)

print("minimap multi-window regression: ok")
print(
	("minimap performance: scrollbar %.3f/%.3f ms, content %.3f/%.3f ms (2/1 mirrors), cropped layout %.3f ms"):format(
		two_mirror_scroll_ms,
		one_mirror_scroll_ms,
		two_mirror_content_ms,
		one_mirror_content_ms,
		two_mirror_layout_ms
	)
)
