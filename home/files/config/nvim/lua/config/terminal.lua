local M = {}

-- Each pane is a terminal tab group. Only the active tab in a group owns its
-- window; inactive tabs keep their terminal buffers and jobs in the background.
local state = {
	groups = {},
	active_group = nil,
	tabs_by_id = {},
	tabs_by_buf = {},
	next_group_id = 1,
	next_tab_id = 1,
	height = nil,
	augroup = nil,
	setup = false,
}

local remove_tab

local function use_compact_auto_open_height()
	local configured_height = vim.tbl_get(Snacks.config, "terminal", "win", "height")
	if type(configured_height) == "number" then
		state.height = configured_height / 2
	end
end

local function group_index(group)
	if not group then
		return nil
	end
	for index, candidate in ipairs(state.groups) do
		if candidate == group then
			return index
		end
	end
end

local function tab_index(group, id)
	if not group then
		return nil
	end
	for index, tab in ipairs(group.tabs) do
		if tab.id == id then
			return index
		end
	end
end

local function valid_tab(tab)
	return tab and not tab.removed and tab.terminal and tab.terminal.buf and vim.api.nvim_buf_is_valid(tab.terminal.buf)
end

local function active_tab(group)
	local index = group and tab_index(group, group.active)
	return index and group.tabs[index] or nil
end

local function terminal_visible(tab)
	return valid_tab(tab)
		and tab.terminal:valid()
		and vim.api.nvim_win_get_tabpage(tab.terminal.win) == vim.api.nvim_get_current_tabpage()
end

local function group_for_buf(buf)
	local tab = state.tabs_by_buf[buf]
	return valid_tab(tab) and tab.group or nil
end

local function group_for_win(win)
	if not win or not vim.api.nvim_win_is_valid(win) then
		return nil
	end

	local id = vim.w[win].dotfiles_terminal_group
	if id then
		for _, group in ipairs(state.groups) do
			if group.id == id then
				return group
			end
		end
	end

	return group_for_buf(vim.api.nvim_win_get_buf(win))
end

local function current_group()
	local group = group_for_buf(vim.api.nvim_get_current_buf())
	if group then
		state.active_group = group.id
		return group
	end

	for _, candidate in ipairs(state.groups) do
		if candidate.id == state.active_group then
			return candidate
		end
	end

	return state.groups[1]
end

local function create_group(after)
	local group = {
		id = state.next_group_id,
		tabs = {},
		active = nil,
	}
	state.next_group_id = state.next_group_id + 1

	local index = group_index(after)
	if index then
		table.insert(state.groups, index + 1, group)
	else
		table.insert(state.groups, group)
	end
	state.active_group = group.id
	return group
end

local function drop_group(group)
	local index = group_index(group)
	if not index then
		return
	end

	table.remove(state.groups, index)
	group.removed = true
	if state.active_group == group.id then
		local replacement = state.groups[math.min(index, #state.groups)] or state.groups[index - 1]
		state.active_group = replacement and replacement.id or nil
	end
end

local function workspace_visible_count()
	local count = 0
	for _, group in ipairs(state.groups) do
		if terminal_visible(active_tab(group)) then
			count = count + 1
		end
	end
	return count
end

local function winbar_focused()
	local win = tonumber(vim.g.statusline_winid)
	return not win or win == 0 or win == vim.api.nvim_get_current_win()
end

local function redraw_winbars()
	if not vim.api.nvim__redraw then
		vim.cmd.redrawstatus()
		return
	end

	for _, group in ipairs(state.groups) do
		local tab = active_tab(group)
		if terminal_visible(tab) then
			vim.api.nvim__redraw({ win = tab.terminal.win, valid = false, flush = false, cursor = false })
		end
	end
end

local function remember_height()
	for _, group in ipairs(state.groups) do
		local tab = active_tab(group)
		if terminal_visible(tab) then
			state.height = vim.api.nvim_win_get_height(tab.terminal.win)
			return
		end
	end
end

local function escape_statusline(text)
	return text:gsub("%%", "%%%%")
end

local function shell_name(cmd)
	if type(cmd) == "table" then
		return vim.fs.basename(cmd[1] or vim.o.shell)
	end
	if type(cmd) == "string" and cmd ~= "" then
		return vim.fs.basename(vim.split(cmd, "%s+", { trimempty = true })[1] or vim.o.shell)
	end
	return vim.fs.basename(vim.o.shell)
end

local function tab_title(tab)
	if valid_tab(tab) then
		local title = vim.b[tab.terminal.buf].term_title
		if type(title) == "string" and title ~= "" then
			if title:match("^term://") then
				return tab.label
			end
			title = vim.trim(title:gsub("[%c\r\n]", " "))
			if title ~= "" then
				return vim.fn.strcharpart(title, 0, 24)
			end
		end
	end
	return tab.label
end

local function normalize_terminal_window(tab)
	local terminal = tab.terminal
	terminal.opts.position = "bottom"
	terminal.opts.relative = "editor"
	terminal.opts.stack = true
	terminal.opts.win = nil
	if state.height then
		terminal.opts.height = state.height
	end

	local win = terminal.win
	if win and vim.api.nvim_win_is_valid(win) then
		vim.w[win].snacks_win = {
			id = terminal.id,
			position = "bottom",
			relative = "editor",
			stack = true,
		}
		vim.w[win].dotfiles_terminal_group = tab.group.id
	end
end

local function detach_terminal(tab)
	if not tab or not tab.terminal then
		return nil
	end

	local terminal = tab.terminal
	local win = terminal.win
	if terminal.augroup then
		pcall(vim.api.nvim_del_augroup_by_id, terminal.augroup)
		terminal.augroup = nil
	end
	terminal.win = nil
	return win and vim.api.nvim_win_is_valid(win) and win or nil
end

local function show_existing_terminal(tab, layout)
	if not valid_tab(tab) then
		return false, "terminal buffer is no longer valid"
	end

	local terminal = tab.terminal
	if layout.current and vim.api.nvim_win_is_valid(layout.current) then
		vim.api.nvim_set_current_win(layout.current)
	end
	terminal.opts.position = layout.position
	terminal.opts.relative = layout.relative or "editor"
	terminal.opts.win = layout.parent
	terminal.opts.stack = false
	terminal.opts.enter = true
	if state.height then
		terminal.opts.height = state.height
	end
	if layout.width then
		terminal.opts.width = layout.width
	end

	local ok, err = pcall(function()
		terminal:show()
	end)
	normalize_terminal_window(tab)
	return ok, err
end

local function focus_tab(tab)
	if terminal_visible(tab) then
		state.active_group = tab.group.id
		tab.terminal:focus()
	end
end

local function register_lifecycle(tab)
	local buf = tab.terminal.buf
	vim.api.nvim_create_autocmd("TermClose", {
		group = state.augroup,
		buffer = buf,
		once = true,
		callback = function()
			vim.schedule(function()
				if not tab.removed then
					remove_tab(tab, true)
				end
			end)
		end,
	})
	vim.api.nvim_create_autocmd("BufWipeout", {
		group = state.augroup,
		buffer = buf,
		once = true,
		callback = function()
			vim.schedule(function()
				if not tab.removed then
					remove_tab(tab, false)
				end
			end)
		end,
	})
end

local function create_tab(group, opts, layout)
	local id = state.next_tab_id
	state.next_tab_id = state.next_tab_id + 1
	local tab = {
		id = id,
		group = group,
		cwd = opts.cwd or vim.fn.getcwd(0),
		label = opts.label or shell_name(opts.cmd),
	}

	local win = {
		position = layout.position,
		relative = layout.relative or "editor",
		win = layout.parent,
		stack = false,
		enter = true,
	}
	if state.height then
		win.height = state.height
	end
	if layout.width then
		win.width = layout.width
	end
	if layout.current and vim.api.nvim_win_is_valid(layout.current) then
		vim.api.nvim_set_current_win(layout.current)
	end

	local ok, terminal = pcall(function()
		return Snacks.terminal.open(opts.cmd, {
			count = id,
			cwd = tab.cwd,
			auto_close = false,
			win = win,
		})
	end)
	if not ok then
		return nil, terminal
	end

	tab.terminal = terminal
	table.insert(group.tabs, tab)
	group.active = id
	state.tabs_by_id[id] = tab
	state.tabs_by_buf[terminal.buf] = tab
	normalize_terminal_window(tab)
	register_lifecycle(tab)
	return tab
end

local function show_workspace(target_group)
	local parent
	for _, group in ipairs(state.groups) do
		local tab = active_tab(group)
		if valid_tab(tab) then
			local layout
			if parent then
				layout = { position = "right", relative = "win", parent = parent, width = 0.5 }
			else
				layout = { position = "bottom" }
			end
			local ok, err = show_existing_terminal(tab, layout)
			if ok then
				parent = tab.terminal.win
			else
				vim.notify(("Failed to show terminal pane: %s"):format(err), vim.log.levels.ERROR)
			end
		end
	end

	local group = target_group or current_group()
	local tab = active_tab(group)
	if terminal_visible(tab) then
		focus_tab(tab)
	end
	redraw_winbars()
end

local function hide_workspace()
	remember_height()
	for index = #state.groups, 1, -1 do
		local tab = active_tab(state.groups[index])
		if terminal_visible(tab) then
			tab.terminal:hide()
		end
	end
	redraw_winbars()
end

local function ensure_workspace_visible(target_group)
	local visible = workspace_visible_count()
	if visible == #state.groups and visible > 0 then
		return
	end
	if visible > 0 then
		hide_workspace()
	end
	show_workspace(target_group)
end

remove_tab = function(tab, close_terminal)
	if not tab or tab.removed then
		return
	end

	local group = tab.group
	local index = tab_index(group, tab.id)
	if not index then
		return
	end

	local was_active = group.active == tab.id
	local terminal = tab.terminal
	local win = terminal and terminal.win
	win = win and vim.api.nvim_win_is_valid(win) and win or nil

	tab.removed = true
	table.remove(group.tabs, index)
	state.tabs_by_id[tab.id] = nil
	if terminal and terminal.buf then
		state.tabs_by_buf[terminal.buf] = nil
	end

	local replacement
	if was_active then
		replacement = group.tabs[math.min(index, #group.tabs)] or group.tabs[index - 1]
		group.active = replacement and replacement.id or nil
	end

	if replacement and win then
		detach_terminal(tab)
		local ok, err = show_existing_terminal(replacement, { position = "current", current = win })
		if not ok then
			vim.notify(("Failed to select replacement terminal: %s"):format(err), vim.log.levels.ERROR)
		end
	elseif not replacement and #group.tabs == 0 then
		drop_group(group)
	end

	if terminal and close_terminal then
		pcall(function()
			terminal:close()
		end)
	elseif not replacement and win and vim.w[win].dotfiles_terminal_group == group.id then
		pcall(vim.api.nvim_win_close, win, true)
	end

	if replacement then
		state.active_group = group.id
		focus_tab(replacement)
	end
	redraw_winbars()
end

local function prune_invalid_tabs()
	local invalid = {}
	for _, group in ipairs(state.groups) do
		for _, tab in ipairs(group.tabs) do
			if not valid_tab(tab) then
				invalid[#invalid + 1] = tab
			end
		end
	end
	for _, tab in ipairs(invalid) do
		remove_tab(tab, false)
	end
end

local function select_tab(tab)
	if not valid_tab(tab) then
		return
	end

	local group = tab.group
	local current = active_tab(group)
	state.active_group = group.id
	if current == tab then
		ensure_workspace_visible(group)
		focus_tab(tab)
		return
	end

	ensure_workspace_visible(group)
	current = active_tab(group)
	local win = terminal_visible(current) and detach_terminal(current) or nil
	group.active = tab.id
	if win then
		local ok, err = show_existing_terminal(tab, { position = "current", current = win })
		if not ok then
			vim.notify(("Failed to select terminal tab: %s"):format(err), vim.log.levels.ERROR)
		end
	else
		show_workspace(group)
	end
	focus_tab(tab)
	redraw_winbars()
end

function M.setup()
	if state.setup then
		return
	end
	state.setup = true
	local auto_open = vim.env.NVIM_AUTO_TERMINAL == "1"
	local workspace_mode = vim.env.NVIM_WORKSPACE_MODE == "1"
	vim.env.NVIM_AUTO_TERMINAL = nil
	vim.env.NVIM_WORKSPACE_MODE = nil
	if auto_open then
		use_compact_auto_open_height()
	end

	require("config.tab_pill").set_terminal_highlights()

	state.augroup = vim.api.nvim_create_augroup("dotfiles-terminal-tabs", { clear = true })
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = state.augroup,
		callback = function()
			require("config.tab_pill").set_terminal_highlights()
			redraw_winbars()
		end,
	})
	vim.api.nvim_create_autocmd("BufEnter", {
		group = state.augroup,
		callback = function(args)
			local group = group_for_buf(args.buf)
			if group then
				state.active_group = group.id
				redraw_winbars()
			end
		end,
	})
	vim.api.nvim_create_autocmd("WinEnter", {
		group = state.augroup,
		callback = redraw_winbars,
	})

	if auto_open and not workspace_mode then
		vim.api.nvim_create_autocmd("VimEnter", {
			group = state.augroup,
			once = true,
			callback = function()
				-- Let any startup layouts settle before opening the bottom pane.
				vim.defer_fn(function()
					local previous_win = vim.api.nvim_get_current_win()
					local previous_mode = vim.api.nvim_get_mode().mode
					M.toggle()

					if vim.api.nvim_win_is_valid(previous_win) then
						vim.api.nvim_set_current_win(previous_win)
						if previous_mode == "t" or previous_mode:sub(1, 1) == "i" then
							vim.cmd.startinsert()
						end
					end
				end, 150)
			end,
		})
	end

	vim.api.nvim_create_user_command("TerminalToggle", M.toggle, { force = true })
	vim.api.nvim_create_user_command("TerminalNew", M.new, { force = true })
	vim.api.nvim_create_user_command("TerminalSplit", M.split, { force = true })
	vim.api.nvim_create_user_command("TerminalNext", M.next, { force = true })
	vim.api.nvim_create_user_command("TerminalPrevious", M.previous, { force = true })
	vim.api.nvim_create_user_command("TerminalClose", function(opts)
		if opts.args == "" then
			M.close()
		else
			M.close_index(tonumber(opts.args))
		end
	end, { force = true, nargs = "?" })
	vim.api.nvim_create_user_command("TerminalSelect", function(opts)
		M.select(tonumber(opts.args))
	end, { force = true, nargs = 1 })

	_G.dotfiles_terminal_winbar = M.winbar
	_G.dotfiles_terminal_tab_click = M.click

	for index = 1, 9 do
		local tab_index_to_select = index
		vim.keymap.set("n", "<leader>T" .. index, function()
			M.select(tab_index_to_select)
		end, { desc = "Select terminal tab " .. index })
		vim.keymap.set("t", "<C-\\>" .. index, function()
			M.select(tab_index_to_select)
		end, { desc = "Select terminal tab " .. index })
	end
end

function M.new(opts)
	opts = type(opts) == "table" and opts or {}
	prune_invalid_tabs()

	local group = current_group()
	if not group then
		group = create_group()
	elseif #group.tabs > 0 then
		ensure_workspace_visible(group)
	end

	local previous = active_tab(group)
	local win = terminal_visible(previous) and detach_terminal(previous) or nil
	local layout = win and { position = "current", current = win } or { position = "bottom" }
	local tab, err = create_tab(group, opts, layout)
	if not tab then
		if previous and win then
			show_existing_terminal(previous, { position = "current", current = win })
			group.active = previous.id
		elseif #group.tabs == 0 then
			drop_group(group)
		end
		error(err)
	end

	state.active_group = group.id
	focus_tab(tab)
	redraw_winbars()
	return tab
end

function M.split(opts)
	opts = type(opts) == "table" and opts or {}
	prune_invalid_tabs()
	local source = current_group()
	if not source then
		return M.new(opts)
	end

	ensure_workspace_visible(source)
	local source_tab = active_tab(source)
	local parent = terminal_visible(source_tab) and source_tab.terminal.win or nil
	if not parent then
		return M.new(opts)
	end

	local group = create_group(source)
	local tab, err = create_tab(group, opts, {
		position = "right",
		relative = "win",
		parent = parent,
		width = 0.5,
	})
	if not tab then
		drop_group(group)
		focus_tab(source_tab)
		error(err)
	end

	state.active_group = group.id
	focus_tab(tab)
	redraw_winbars()
	return tab
end

function M.toggle()
	prune_invalid_tabs()
	if workspace_visible_count() > 0 then
		hide_workspace()
		return
	end
	if #state.groups == 0 then
		return M.new()
	end
	show_workspace(current_group())
end

function M.select(index)
	prune_invalid_tabs()
	local group = current_group()
	local tab = group and group.tabs[index] or nil
	if tab then
		select_tab(tab)
	end
end

local function cycle(delta)
	prune_invalid_tabs()
	local group = current_group()
	if not group or #group.tabs == 0 then
		return M.new()
	end

	local index = tab_index(group, group.active) or 1
	index = ((index - 1 + delta) % #group.tabs) + 1
	select_tab(group.tabs[index])
end

function M.next()
	cycle(1)
end

function M.previous()
	cycle(-1)
end

function M.close(id)
	prune_invalid_tabs()
	local tab
	if id then
		tab = state.tabs_by_id[id]
	else
		tab = active_tab(current_group())
	end
	if tab then
		remove_tab(tab, true)
	end
end

function M.close_index(index)
	prune_invalid_tabs()
	local group = current_group()
	local tab = group and group.tabs[index] or nil
	if tab then
		remove_tab(tab, true)
	end
end

function M.winbar()
	local win = tonumber(vim.g.statusline_winid)
	if not win or win == 0 then
		win = vim.api.nvim_get_current_win()
	end
	local group = group_for_win(win)
	local segments = { "%#TerminalTabFill# " }
	if not group then
		return table.concat(segments)
	end

	local suffix = winbar_focused() and "" or "Dim"
	for index, tab in ipairs(group.tabs) do
		local active = tab.id == group.active
		local body = (active and "TerminalTabActive" or "TerminalTabInactive") .. suffix
		local edge = (active and "TerminalTabActiveEdge" or "TerminalTabInactiveEdge") .. suffix
		local label = escape_statusline((" %d 󰆍 %s "):format(index, tab_title(tab)))

		segments[#segments + 1] = ("%%%d@v:lua.dotfiles_terminal_tab_click@"):format(tab.id)
		segments[#segments + 1] = ("%%#%s#"):format(edge)
		segments[#segments + 1] = ("%%#%s#%s"):format(body, label)
		segments[#segments + 1] = ("%%#%s#"):format(edge)
		segments[#segments + 1] = "%T%#TerminalTabFill# "
	end

	return table.concat(segments)
end

function M.click(id, _, button)
	vim.schedule(function()
		local tab = state.tabs_by_id[id]
		if not tab then
			return
		end
		if button == "m" then
			remove_tab(tab, true)
		else
			select_tab(tab)
		end
	end)
end

return M
