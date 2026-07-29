local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
local mini_map_root = vim.fs.joinpath(vim.fn.stdpath("data"), "lazy/mini.map")

local child = vim.fn.jobstart({ vim.v.progpath, "--embed", "-u", "NONE", "-i", "NONE", "-n" }, { rpc = true })
assert(child > 0, "failed to start composed-screen Neovim child")
local function request(method, ...)
	return vim.rpcrequest(child, method, ...)
end

local function finish()
	pcall(request, "nvim_command", "qa!")
	local status = vim.fn.jobwait({ child }, 2000)[1]
	if status == -1 then
		vim.fn.jobstop(child)
		vim.fn.jobwait({ child }, 2000)
	end
end

local ok, result = xpcall(function()
	request("nvim_ui_attach", 80, 24, { rgb = true, ext_multigrid = false })
	return request(
		"nvim_exec_lua",
		[[
local dotfiles_root, nvim_root, mini_map_root = ...
vim.opt.runtimepath:prepend(nvim_root)
vim.opt.runtimepath:prepend(mini_map_root)
package.path = table.concat({
  vim.fs.joinpath(nvim_root, 'lua/?.lua'),
  vim.fs.joinpath(nvim_root, 'lua/?/init.lua'),
  vim.fs.joinpath(mini_map_root, 'lua/?.lua'),
  package.path,
}, ';')
local function upvalue(fn, expected_name)
  for index = 1, math.huge do
    local name, value = debug.getupvalue(fn, index)
    if not name then break end
    if name == expected_name then return value end
  end
  error('missing upvalue: ' .. expected_name)
end
local function wait_for(predicate, message)
  assert(vim.wait(2000, predicate, 10), message)
end
vim.o.laststatus, vim.o.showtabline = 0, 0
vim.o.sidescroll, vim.o.sidescrolloff = 1, 4
local specs = dofile(vim.fs.joinpath(nvim_root, 'lua/plugins/minimap.lua'))
local setup_code_layout = upvalue(specs[1].config, 'setup_code_layout')
local set_minimap_highlights = upvalue(specs[1].config, 'set_minimap_highlights')
local map = require('mini.map')
local source = vim.api.nvim_get_current_win()
vim.wo[source].cursorline, vim.wo[source].foldcolumn = true, '0'
vim.wo[source].number, vim.wo[source].relativenumber = false, false
vim.wo[source].signcolumn, vim.wo[source].statuscolumn, vim.wo[source].wrap = 'no', '', false
vim.api.nvim_set_hl(0, 'Normal', { fg = '#cdd6f4', bg = '#11111b' })
vim.api.nvim_set_hl(0, 'CursorLine', { bg = '#45475a' })
local lines = { ('SOURCE-ONE-'):rep(12), ('SOURCE-TWO-'):rep(12), ('SOURCE-THREE-'):rep(12), ('EOF-RESTORED-'):rep(12) }
vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
vim.api.nvim_win_set_cursor(source, { 1, 0 })
map.setup({ integrations = {}, symbols = { encode = map.gen_encode_symbols.dot('4x2') }, window = { focusable = false, show_integration_count = false, width = 12, winblend = 0, zindex = 30 } })
set_minimap_highlights()
setup_code_layout(map)
map.open()
local manager = map._dotfiles_multi_window_manager
local tabpage = vim.api.nvim_get_current_tabpage()
wait_for(function() local win = map.current.win_data[tabpage]; return win and vim.api.nvim_win_is_valid(win) and manager.rendered_maps[win] end, 'minimap display did not initialize')
local map_win = map.current.win_data[tabpage]
local map_buf = vim.api.nvim_win_get_buf(map_win)
vim.api.nvim_buf_clear_namespace(map_buf, -1, 0, -1)
vim.api.nvim_buf_set_lines(map_buf, 0, -1, false, { '┃⠁', '⠀', '⠂' })
manager.schedule({ lines = true, integrations = false, scrollbar = false })
wait_for(function() local display = manager.rendered_maps[map_win]; return display and vim.api.nvim_win_is_valid(display.win) and vim.api.nvim_win_get_height(display.win) == 3 end, 'display did not match encoded EOF')
local position, source_width, map_width = vim.api.nvim_win_get_position(source), vim.api.nvim_win_get_width(source), vim.api.nvim_win_get_width(map_win)
local row, map_left, pane_right = position[1] + 1, position[2] + source_width - map_width + 1, position[2] + source_width
assert(vim.api.nvim_get_option_value('sidescrolloff', { scope = 'local', win = source }) == 4 + map_width, 'source did not reserve the minimap width')
vim.api.nvim_win_set_cursor(source, { 1, 0 })
for column = 1, #lines[1] - 1 do
  vim.api.nvim_win_set_cursor(source, { 1, column })
  vim.cmd.redraw()
end
local source_view = vim.api.nvim_win_call(source, vim.fn.winsaveview)
local cursor_screen_column = position[2] + vim.api.nvim_win_call(source, function() return vim.fn.virtcol('.') - source_view.leftcol end)
assert(cursor_screen_column < map_left, 'nowrap cursor entered the minimap interval')
assert(map_left - cursor_screen_column - 1 >= 4, 'nowrap cursor lost the original horizontal context')
vim.api.nvim_win_set_cursor(source, { 1, 0 })
vim.api.nvim_win_call(source, function() vim.fn.winrestview({ leftcol = 0 }) end)
vim.cmd.redraw({ bang = true })
local source_cursorline_attr = vim.fn.screenattr(row, position[2] + 1)
local minimap_blank_attr = vim.fn.screenattr(row, pane_right)
local function assert_occupied(screen_row, source_line, expected_attr, message)
 assert(expected_attr ~= source_cursorline_attr, message .. ' retained the source CursorLine attribute')
 for column = map_left, pane_right do
  local source_column = column - position[2]
  assert(vim.fn.screenstring(screen_row, column) ~= source_line:sub(source_column, source_column), message .. ' leaked source glyph at ' .. column)
  assert(vim.fn.screenattr(screen_row, column) == expected_attr, message .. ' changed attribute at ' .. column)
 end
end
assert_occupied(row, lines[1], minimap_blank_attr, 'encoded row')
assert_occupied(row + 1, lines[2], minimap_blank_attr, 'encoded blank row')
vim.api.nvim_win_set_cursor(source, { 4, 0 })
vim.cmd.redraw({ bang = true })
local eof_row = row + 3
local source_eof_attr = vim.fn.screenattr(eof_row, position[2] + 1)
for column = map_left, pane_right do
  local source_column = column - position[2]
  assert(vim.fn.screenstring(eof_row, column) == lines[4]:sub(source_column, source_column), 'below EOF source glyph missing at ' .. column)
  assert(vim.fn.screenattr(eof_row, column) == source_eof_attr, 'below EOF CursorLine missing at ' .. column)
end
vim.api.nvim_set_current_win(source)
map.toggle_focus()
wait_for(function()
  local display = manager.rendered_maps[map_win]
  return manager.focused and vim.api.nvim_get_current_win() == map_win and vim.api.nvim_win_get_config(map_win).hide and display and vim.api.nvim_win_is_valid(display.win) and vim.api.nvim_win_get_height(display.win) == 3 and vim.wo[display.win].cursorline and vim.api.nvim_win_get_cursor(display.win)[1] == vim.api.nvim_win_get_cursor(map_win)[1]
end, 'focused minimap did not retain hidden state and cropped display')
vim.cmd.redraw({ bang = true })
local focused_row = row + vim.api.nvim_win_get_cursor(map_win)[1] - 1
local focused_right_attr = vim.fn.screenattr(focused_row, pane_right)
assert(focused_right_attr ~= minimap_blank_attr, 'focused display lost its cursor rail')
assert_occupied(focused_row, lines[focused_row - row + 1], focused_right_attr, 'focused encoded row')
return true
]],
		{ dotfiles_root, nvim_root, mini_map_root }
	)
end, debug.traceback)
finish()
assert(ok, result)
assert(result, "composed-screen child did not complete")
print("minimap composed-screen regression: ok")
