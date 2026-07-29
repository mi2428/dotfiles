local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
local mini_map_root = vim.fs.joinpath(vim.fn.stdpath("data"), "lazy/mini.map")

local child = vim.fn.jobstart({ vim.v.progpath, "--embed", "-u", "NONE", "-i", "NONE", "-n" }, { rpc = true })
assert(child > 0, "failed to start wrap-screen Neovim child")
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
		[=[
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
local specs = dofile(vim.fs.joinpath(nvim_root, 'lua/plugins/minimap.lua'))
local setup_code_layout = upvalue(specs[1].config, 'setup_code_layout')
local set_minimap_highlights = upvalue(specs[1].config, 'set_minimap_highlights')
local map = require('mini.map')
local source = vim.api.nvim_get_current_win()
vim.wo[source].breakindent, vim.wo[source].cursorline, vim.wo[source].wrap = false, true, true
vim.wo[source].foldcolumn, vim.wo[source].number, vim.wo[source].relativenumber = '0', false, false
vim.wo[source].signcolumn, vim.wo[source].statuscolumn = 'no', ''
vim.api.nvim_set_hl(0, 'Normal', { fg = '#cdd6f4', bg = '#11111b' })
local source_line = string.rep('x', 216)
vim.api.nvim_buf_set_lines(0, 0, -1, false, { source_line, 'after' })
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
vim.api.nvim_buf_set_lines(map_buf, 0, -1, false, { '┃⠁', '⠂' })
manager.schedule({ wrap = true, display = true })
wait_for(function()
  local display = manager.rendered_maps[map_win]
  local state = manager.wrap_margins[source]
  return display and vim.api.nvim_win_get_height(display.win) == 2 and state and #vim.api.nvim_buf_get_extmarks(0, state.namespace, 0, -1, {}) == 2
end, 'wrapped rows did not initialize')
vim.cmd.redraw({ bang = true })
local position = vim.api.nvim_win_get_position(source)
local pane_left, pane_right = position[2] + 1, position[2] + vim.api.nvim_win_get_width(source)
local map_left = pane_right - vim.api.nvim_win_get_width(map_win) + 1
assert(map_left == 69 and pane_right == 80, 'fixture width changed')
for screen_row = 1, 2 do
  for column = pane_left, map_left - 1 do
    assert(vim.fn.screenstring(screen_row, column) == 'x', ('protected row %d lost source at %d'):format(screen_row, column))
  end
  for column = map_left, pane_right do
    assert(vim.fn.screenstring(screen_row, column) ~= 'x', ('protected row %d leaked source under minimap at %d'):format(screen_row, column))
  end
end
for column = pane_left, pane_right do
  assert(vim.fn.screenstring(3, column) == 'x', ('row below minimap EOF did not reclaim column %d'):format(column))
end
local restored_cursorline_attr = vim.fn.screenattr(3, pane_left)
for column = pane_left, pane_right do
  assert(vim.fn.screenattr(3, column) == restored_cursorline_attr, ('row below minimap EOF lost CursorLine at %d'):format(column))
end
local state = manager.wrap_margins[source]
local marks = vim.api.nvim_buf_get_extmarks(0, state.namespace, 0, -1, { details = true })
assert(marks[1][3] == 68 and marks[2][3] == 136, 'wrap padding used wrong source columns')
return true
]=],
		{ dotfiles_root, nvim_root, mini_map_root }
	)
end, debug.traceback)
finish()
assert(ok, result)
assert(result, "wrap-screen child did not complete")
print("minimap wrap composed-screen regression: ok")
