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
vim.o.sidescrolloff = 5
vim.api.nvim_set_option_value("sidescrolloff", -1, { scope = "local", win = 0 })
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

local original_schedule = manager.schedule
local managed_event_schedule_count = 0
manager.schedule = function(parts)
	managed_event_schedule_count = managed_event_schedule_count + 1
	return original_schedule(parts)
end
manager.managing_windows = manager.managing_windows + 1
vim.api.nvim_exec_autocmds("WinNew", { group = "dotfiles-mini-map-code-layout", modeline = false })
vim.api.nvim_exec_autocmds("WinClosed", { group = "dotfiles-mini-map-code-layout", modeline = false })
manager.managing_windows = manager.managing_windows - 1
assert(managed_event_schedule_count == 0, "managed window lifecycle events recursively scheduled a refresh")
manager.schedule = original_schedule

local function wait_for(predicate, message)
	assert(vim.wait(2000, predicate, 10), message)
end

local first = vim.api.nvim_get_current_win()
wait_for(function()
	local state = manager.source_margins[first]
	return state
		and state.restore_local == -1
		and vim.api.nvim_get_option_value("sidescrolloff", { scope = "local", win = first }) == 17
end, "global sidescrolloff base did not receive exactly one minimap reservation")
vim.api.nvim_set_option_value("sidescrolloff", 9, { scope = "local", win = first })
wait_for(function()
	local state = manager.source_margins[first]
	return state
		and state.restore_local == 9
		and vim.api.nvim_get_option_value("sidescrolloff", { scope = "local", win = first }) == 21
end, "custom local sidescrolloff did not replace the inherited minimap base")

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
		"hidden state windows must map EndOfBuffer to the minimap background"
	)
	local display = assert(manager.rendered_maps[map_win], "minimap has no visible display float")
	assert(vim.api.nvim_win_is_valid(display.win), "minimap display float is invalid")
	assert(
		vim.api.nvim_win_get_buf(display.win) == vim.api.nvim_win_get_buf(map_win),
		"display must use state map buffer"
	)
	local expected_left = source_position[2] + vim.api.nvim_win_get_width(source_win) - config.width
	local display_config = vim.api.nvim_win_get_config(display.win)
	assert(display_config.row == source_position[1], "display float is vertically misplaced")
	assert(display_config.col == expected_left, "display float is horizontally misplaced")
	assert(
		display_config.height == math.min(vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(map_win)), config.height),
		"display height does not match encoded span"
	)
	assert(display_config.width == config.width, "display must cover from rail to pane edge")
	assert(vim.wo[display.win].winblend == 0, "display occupied interval must be opaque")
	return map_win
end

vim.cmd.vsplit()
local second = vim.api.nvim_get_current_win()
wait_for(function()
	return count_mirrors() == 1
end, "vertical split did not create a second minimap")

assert(manager.prepare_source_margin_transfer(first), "popup source margin transfer preparation was rejected")
assert(manager.source_margins[first] == nil and manager.detached_source_margins[first] == 9)
assert(
	vim.api.nvim_get_option_value("sidescrolloff", { scope = "local", win = first }) == 9,
	"popup source retained its reserved margin before buffer detachment"
)
assert(manager.discard_source_margin_transfer(first), "popup source margin transfer cancellation was rejected")
assert(manager.detached_source_margins[first] == nil, "cancelled popup source margin metadata survived")
assert(not manager.discard_source_margin_transfer(first), "discard reported absent popup margin metadata as present")
manager.detached_source_margins[-12345] = 7
assert(manager.discard_source_margin_transfer(-12345), "invalid window id metadata was not discarded")
assert(manager.detached_source_margins[-12345] == nil, "invalid window id metadata survived discard")
map.refresh({}, { layout = true, integrations = false, lines = false, scrollbar = false })
wait_for(function()
	local state = manager.source_margins[first]
	return state
		and state.restore_local == 9
		and vim.api.nvim_get_option_value("sidescrolloff", { scope = "local", win = first }) == 21
end, "cancelled popup source margin did not return to ordinary minimap ownership")
assert(manager.prepare_source_margin_transfer(first), "re-preparing popup source margin transfer was rejected")
assert(manager.source_margins[first] == nil and manager.detached_source_margins[first] == 9)
local popup_child
vim.api.nvim_win_call(first, function()
	popup_child = vim.api.nvim_open_win(vim.api.nvim_win_get_buf(first), false, {
		relative = "editor",
		row = 1,
		col = 1,
		width = 60,
		height = 10,
		border = { "", "", "", "", "", "", "", "│" },
		style = "minimal",
	})
end)
vim.w[popup_child].dotfiles_git_diff_peek_child = true
assert(manager.inherit_source_margin(popup_child, first), "explicit popup margin inheritance was rejected")
assert(
	manager.source_margins[popup_child].restore_local == 9,
	"popup child did not inherit the parent's unreserved margin"
)
assert(not manager.inherit_source_margin(-1, first), "invalid popup child margin inheritance succeeded")
map.refresh({}, { layout = true, integrations = false, lines = true, scrollbar = false })
local popup_map
wait_for(function()
	popup_map = manager.map_window_for_source(popup_child)
	return popup_map and vim.api.nvim_win_is_valid(popup_map) and manager.rendered_maps[popup_map] ~= nil
end, "bordered popup child did not receive a minimap")
local popup_position = vim.api.nvim_win_get_position(popup_child)
local popup_right = popup_position[2] + 1 + vim.api.nvim_win_get_width(popup_child)
local popup_map_config = vim.api.nvim_win_get_config(popup_map)
local popup_display_config = vim.api.nvim_win_get_config(manager.rendered_maps[popup_map].win)
assert(popup_map_config.col == popup_right, "popup minimap ignored its one-cell left border")
assert(
	popup_display_config.col + popup_display_config.width == popup_right,
	"popup minimap display left a one-cell right margin"
)
vim.api.nvim_win_close(popup_child, true)
wait_for(function()
	return manager.source_margins[popup_child] == nil
end, "closed popup child leaked inherited margin metadata")

vim.w[first].dotfiles_disable_minimap = true
map.refresh({}, { layout = true, integrations = false, lines = false, scrollbar = false })
wait_for(function()
	return count_mirrors() == 0 and manager.map_window_for_source(first) == nil
end, "a window-local minimap opt-out did not remove the inactive split map")
vim.api.nvim_set_current_win(first)
map.refresh({}, { layout = true, integrations = false, lines = false, scrollbar = false })
assert(map._dotfiles_source_win == second, "a minimap-disabled split must not take native map ownership")
vim.w[first].dotfiles_disable_minimap = false
vim.api.nvim_set_current_win(second)
map.refresh({}, { layout = true, integrations = false, lines = false, scrollbar = false })
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
local native_view_namespace = assert(namespaces.MiniMapScrollView)
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

vim.cmd("leftabove vnew")
local placeholder_win = vim.api.nvim_get_current_win()
local placeholder_buf = vim.api.nvim_get_current_buf()
assert(vim.api.nvim_buf_get_name(placeholder_buf) == "", "placeholder fixture must be unnamed")
assert(not vim.bo[placeholder_buf].modified, "placeholder fixture must be unmodified")
assert(vim.bo[placeholder_buf].buftype == "", "placeholder fixture must retain an empty buftype")
assert(vim.api.nvim_buf_line_count(placeholder_buf) == 1)
assert(vim.api.nvim_buf_get_lines(placeholder_buf, 0, 1, false)[1] == "")
vim.api.nvim_set_current_win(second)
map.refresh({}, { layout = true, integrations = false, lines = false, scrollbar = false })
wait_for(function()
	local native = manager.map_window_for_source(second)
	return native
		and vim.api.nvim_win_is_valid(native)
		and manager.mirrors[placeholder_win] == nil
		and manager.map_window_for_source(placeholder_win) == nil
end, "an inactive unnamed placeholder received a mirror minimap")
vim.api.nvim_win_close(placeholder_win, true)
vim.api.nvim_buf_delete(placeholder_buf, { force = true })
wait_for(function()
	return count_mirrors() == 1
end, "closing the inactive placeholder changed ordinary mirror ownership")

local focused_native = assert(manager.map_window_for_source(second))
map.toggle_focus()
wait_for(function()
	local display = manager.rendered_maps[focused_native]
	return manager.focused
		and vim.api.nvim_get_current_win() == focused_native
		and vim.api.nvim_win_get_config(focused_native).hide
		and display
		and vim.api.nvim_win_is_valid(display.win)
		and vim.api.nvim_win_get_cursor(display.win)[1] == vim.api.nvim_win_get_cursor(focused_native)[1]
		and vim.wo[display.win].cursorline
end, "focused minimap did not retain its opaque display and focus line")
assert_map_geometry(second)
local focused_display = manager.rendered_maps[focused_native].win
vim.api.nvim_win_set_cursor(focused_native, { 2, 0 })
vim.api.nvim_exec_autocmds("CursorMoved", { modeline = false })
wait_for(function()
	return vim.api.nvim_win_get_cursor(focused_display)[1] == 2 and vim.wo[focused_display].cursorline
end, "focused minimap cursor did not reach the visible display")
map.toggle_focus(true)
wait_for(function()
	return not manager.focused
		and vim.api.nvim_get_current_win() == second
		and vim.api.nvim_win_get_config(focused_native).hide
		and manager.rendered_maps[focused_native]
		and vim.api.nvim_win_is_valid(manager.rendered_maps[focused_native].win)
		and not vim.wo[manager.rendered_maps[focused_native].win].cursorline
end, "leaving minimap focus did not restore the display renderer")
assert_map_geometry(second)

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

local function upvalue_index(fn, expected_name)
	for index = 1, math.huge do
		local name, value = debug.getupvalue(fn, index)
		if not name then
			break
		end
		if name == expected_name then
			return index, value
		end
	end
	error("missing upvalue: " .. expected_name)
end

local function drain_scheduled_work(message)
	for _ = 1, 2 do
		local event_loop_turn_complete = false
		vim.schedule(function()
			event_loop_turn_complete = true
		end)
		assert(
			vim.wait(2000, function()
				return event_loop_turn_complete and not manager.scheduled and next(manager.pending) == nil
			end, 1),
			message
		)
	end
end

local function snapshot_displays()
	local snapshot = {}
	for map_win, display in pairs(manager.rendered_maps) do
		local config = vim.api.nvim_win_get_config(display.win)
		snapshot[map_win] = {
			win = display.win,
			row = config.row,
			col = config.col,
			width = config.width,
			height = config.height,
			zindex = config.zindex,
		}
	end
	return snapshot
end

local function assert_displays_unchanged(before, message)
	for map_win, previous in pairs(before) do
		local display = manager.rendered_maps[map_win]
		assert(display and display.win == previous.win, message .. ": display id changed")
		local config = vim.api.nvim_win_get_config(display.win)
		assert(
			config.row == previous.row
				and config.col == previous.col
				and config.width == previous.width
				and config.height == previous.height
				and config.zindex == previous.zindex,
			message .. ": display geometry changed"
		)
	end
	assert(vim.tbl_count(manager.rendered_maps) == vim.tbl_count(before), message .. ": display count changed")
end

local function component_average_ms(iterations, callback)
	collectgarbage("collect")
	local started = vim.uv.hrtime()
	for _ = 1, iterations do
		callback()
	end
	return (vim.uv.hrtime() - started) / 1e6 / iterations
end

local function event_distribution(iterations, callback, message, refresh_count)
	local samples = {}
	for index = 1, iterations do
		drain_scheduled_work(message .. ": work before event did not drain")
		local refreshes_before = refresh_count()
		local started = vim.uv.hrtime()
		callback(index)
		drain_scheduled_work(message .. ": work after event did not drain")
		assert(refresh_count() == refreshes_before + 1, message .. ": did not invoke exactly one wrapped view refresh")
		samples[index] = (vim.uv.hrtime() - started) / 1e6
	end
	table.sort(samples)
	return {
		median = samples[math.ceil(#samples / 2)],
		p95 = samples[math.ceil(#samples * 0.95)],
	}
end

local flush = upvalue(manager.schedule, "flush")
local render_all_maps_index, render_all_maps = upvalue_index(flush, "render_all_maps")
local display_reconciliations = 0
debug.setupvalue(flush, render_all_maps_index, function(...)
	display_reconciliations = display_reconciliations + 1
	return render_all_maps(...)
end)

local original_refresh = map.refresh
local view_refreshes = 0
map.refresh = function(opts, parts)
	if parts and parts.integrations == false and parts.lines == false then
		view_refreshes = view_refreshes + 1
	end
	return original_refresh(opts, parts)
end

local display_before_events = snapshot_displays()
local function native_map_line(source_line)
	local native = assert(manager.map_window_for_source(first))
	local source_rows = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(first))
	local resolution = map.current.opts.symbols.encode.resolution.row
	local rescaled_rows = math.min(source_rows, vim.api.nvim_win_get_height(native) * resolution)
	local rescaled_row = math.floor((rescaled_rows / source_rows) * (source_line - 1)) + 1
	return math.floor((rescaled_row - 1) / resolution) + 1
end

local cursor_moved = event_distribution(
	100,
	function(index)
		vim.api.nvim_win_call(first, function()
			vim.api.nvim_win_set_cursor(first, { 10 + (index % 2), 0 })
			vim.api.nvim_exec_autocmds("CursorMoved", { modeline = false })
		end)
	end,
	"CursorMoved",
	function()
		return view_refreshes
	end
)
assert(display_reconciliations == 0, "CursorMoved reconciled display floats")
assert_displays_unchanged(display_before_events, "CursorMoved")
local native = assert(manager.map_window_for_source(first))
local native_buf = vim.api.nvim_win_get_buf(native)
local cursor_marks = vim.api.nvim_buf_get_extmarks(native_buf, native_line_namespace, 0, -1, {})
assert(#cursor_marks == 1 and cursor_marks[1][2] == native_map_line(10) - 1, "CursorMoved left a stale rail")

vim.api.nvim_win_call(first, function()
	vim.api.nvim_win_set_cursor(first, { 120, 0 })
	vim.fn.winrestview({ topline = 100 })
end)
drain_scheduled_work("WinScrolled fixture did not settle")

local scrolled = event_distribution(
	100,
	function(index)
		vim.api.nvim_win_call(first, function()
			vim.fn.winrestview({ topline = 100 + (index % 2) })
			vim.api.nvim_exec_autocmds("WinScrolled", { modeline = false })
		end)
	end,
	"WinScrolled",
	function()
		return view_refreshes
	end
)
assert(display_reconciliations == 0, "WinScrolled reconciled display floats")
assert_displays_unchanged(display_before_events, "WinScrolled")
local source_view = vim.api.nvim_win_call(first, function()
	return { first = vim.fn.line("w0"), last = vim.fn.line("w$") }
end)
local view_marks = vim.api.nvim_buf_get_extmarks(native_buf, native_view_namespace, 0, -1, {})
local first_view_row = native_map_line(source_view.first) - 1
local last_view_row = native_map_line(source_view.last) - 1
assert(#view_marks == last_view_row - first_view_row + 1, "WinScrolled left a stale viewport rail")
for index, mark in ipairs(view_marks) do
	assert(mark[2] == first_view_row + index - 1, "WinScrolled viewport rail is misplaced")
end
debug.setupvalue(flush, render_all_maps_index, render_all_maps)
map.refresh = original_refresh

assert(cursor_moved.median <= 2 and cursor_moved.p95 <= 5, "CursorMoved end-to-end latency regressed")
assert(scrolled.median <= 2 and scrolled.p95 <= 5, "WinScrolled end-to-end latency regressed")

local benchmark_cursor = 0
local function refresh_moving_mirror_scrollbar()
	benchmark_cursor = (benchmark_cursor % #source_lines) + 1
	vim.api.nvim_win_set_cursor(second, { benchmark_cursor, 0 })
	manager.refresh_scrollbars()
end

local two_mirror_scroll_ms = component_average_ms(1000, refresh_moving_mirror_scrollbar)
local two_mirror_content_ms = component_average_ms(20, manager.refresh_content)

vim.api.nvim_win_close(third, true)
wait_for(function()
	return count_mirrors() == 1
end, "closing a source split leaked its mirror minimap")

local one_mirror_scroll_ms = component_average_ms(1000, refresh_moving_mirror_scrollbar)
local one_mirror_content_ms = component_average_ms(20, manager.refresh_content)
assert(two_mirror_scroll_ms < 1, "two-mirror scrollbar component regressed above 1 ms per cursor update")
assert(one_mirror_scroll_ms < 1, "one-mirror scrollbar component regressed above 1 ms per cursor update")
assert(two_mirror_content_ms < 35, "mixed-geometry content refresh regressed above 35 ms")
assert(one_mirror_content_ms < 5, "one-mirror content refresh regressed above 5 ms")

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
		and manager.rendered_maps[native]
		and vim.api.nvim_win_get_height(manager.rendered_maps[native].win) == 1
end, "an empty source buffer did not retain its visible scrollbar row")
local empty_native = manager.map_window_for_source(active_empty_source)
local empty_line_marks = vim.api.nvim_buf_get_extmarks(
	vim.api.nvim_win_get_buf(empty_native),
	assert(vim.api.nvim_get_namespaces().MiniMapScrollLine),
	0,
	-1,
	{}
)
assert(#empty_line_marks == 1 and empty_line_marks[1][2] == 0, "empty-buffer cursor rail moved from its map origin")

vim.cmd("leftabove 8vnew")
local narrow_source = vim.api.nvim_get_current_win()
wait_for(function()
	local narrow_map = manager.map_window_for_source(narrow_source)
	local display = narrow_map and manager.rendered_maps[narrow_map]
	return narrow_map
		and vim.api.nvim_win_is_valid(narrow_map)
		and vim.api.nvim_win_get_width(narrow_map) == vim.api.nvim_win_get_width(narrow_source)
		and display
		and vim.api.nvim_win_is_valid(display.win)
		and vim.api.nvim_win_get_config(display.win).col == vim.api.nvim_win_get_position(narrow_source)[2]
		and vim.api.nvim_win_get_width(display.win) == vim.api.nvim_win_get_width(narrow_map)
end, "narrow pane did not re-encode and retain its rail inside the source window")
assert_map_geometry(narrow_source)

local display_windows = {}
for _, display in pairs(manager.rendered_maps) do
	display_windows[#display_windows + 1] = display.win
end
map.close()
wait_for(function()
	if count_mirrors() ~= 0 or next(manager.rendered_maps) ~= nil then
		return false
	end
	for _, win in ipairs(display_windows) do
		if vim.api.nvim_win_is_valid(win) then
			return false
		end
	end
	return true
end, "closing mini.map leaked managed display windows")
vim.wait(20, function()
	return false
end)

print("minimap multi-window regression: ok")
print(
	("minimap performance: end-to-end CursorMoved median/p95 %.3f/%.3f ms, WinScrolled %.3f/%.3f ms; component scrollbar %.3f/%.3f ms, content %.3f/%.3f ms (2/1 mirrors)"):format(
		cursor_moved.median,
		cursor_moved.p95,
		scrolled.median,
		scrolled.p95,
		two_mirror_scroll_ms,
		one_mirror_scroll_ms,
		two_mirror_content_ms,
		one_mirror_content_ms
	)
)
