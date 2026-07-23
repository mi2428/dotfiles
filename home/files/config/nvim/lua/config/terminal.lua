local M = {}

-- Each tab owns a terminal buffer/job, while only the selected Snacks window
-- is shown. Hiding and showing that window keeps the bottom panel to one pane.
local state = {
	tabs = {},
	active = nil,
	next_id = 1,
	height = nil,
	setup = false,
}

local function tab_index(id)
	for index, tab in ipairs(state.tabs) do
		if tab.id == id then
			return index
		end
	end
end

local function valid_tab(tab)
	return tab and tab.terminal and tab.terminal.buf and vim.api.nvim_buf_is_valid(tab.terminal.buf)
end

local function current_tab()
	local index = tab_index(state.active)
	return index and state.tabs[index] or nil
end

local function terminal_visible(tab)
	return valid_tab(tab) and tab.terminal.win and vim.api.nvim_win_is_valid(tab.terminal.win)
end

local function terminal_visible_here(tab)
	return terminal_visible(tab)
		and vim.api.nvim_win_get_tabpage(tab.terminal.win) == vim.api.nvim_get_current_tabpage()
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

	for _, tab in ipairs(state.tabs) do
		if terminal_visible(tab) then
			vim.api.nvim__redraw({ win = tab.terminal.win, valid = false, flush = false, cursor = false })
		end
	end
end

local function remember_height(tab)
	if terminal_visible(tab) then
		state.height = vim.api.nvim_win_get_height(tab.terminal.win)
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
			title = title:gsub("[%c\r\n]", " ")
			title = vim.trim(title)
			if title ~= "" then
				return vim.fn.strcharpart(title, 0, 24)
			end
		end
	end
	return tab.label
end

local function hide_other_terminals(selected)
	for _, tab in ipairs(state.tabs) do
		if tab ~= selected and terminal_visible(tab) then
			remember_height(tab)
			tab.terminal:hide()
		end
	end
end

local function show(tab)
	if not valid_tab(tab) then
		return
	end

	hide_other_terminals(tab)
	if terminal_visible(tab) and not terminal_visible_here(tab) then
		remember_height(tab)
		tab.terminal:hide()
	end

	state.active = tab.id
	if state.height then
		tab.terminal.opts.height = state.height
	end
	tab.terminal:show()
	tab.terminal:focus()
	redraw_winbars()
end

local function forget(id, reopen)
	local index = tab_index(id)
	if not index then
		return
	end

	local was_active = state.active == id
	table.remove(state.tabs, index)

	if was_active then
		local replacement = state.tabs[math.min(index, #state.tabs)] or state.tabs[index - 1]
		state.active = replacement and replacement.id or nil
		if reopen and replacement then
			vim.schedule(function()
				show(replacement)
			end)
		end
	end

	redraw_winbars()
end

local function prune_invalid_tabs()
	for index = #state.tabs, 1, -1 do
		local tab = state.tabs[index]
		if not valid_tab(tab) then
			forget(tab.id, false)
		end
	end
end

local function register_lifecycle(tab)
	tab.terminal:on("TermClose", function()
		vim.schedule(function()
			M.close(tab.id)
		end)
	end, { buf = true })

	tab.terminal:on("BufWipeout", function()
		local reopen = terminal_visible(tab)
		vim.schedule(function()
			forget(tab.id, reopen)
		end)
	end, { buf = true })
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

	require("config.tab_pill").set_terminal_highlights()

	local group = vim.api.nvim_create_augroup("dotfiles-terminal-tabs", { clear = true })
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = group,
		callback = function()
			require("config.tab_pill").set_terminal_highlights()
			redraw_winbars()
		end,
	})
	if auto_open and not workspace_mode then
		vim.api.nvim_create_autocmd("VimEnter", {
			group = group,
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
	vim.api.nvim_create_user_command("TerminalNext", M.next, { force = true })
	vim.api.nvim_create_user_command("TerminalPrevious", M.previous, { force = true })
	vim.api.nvim_create_user_command("TerminalClose", function(opts)
		M.close(tonumber(opts.args))
	end, { force = true, nargs = "?" })
	vim.api.nvim_create_user_command("TerminalSelect", function(opts)
		M.select(tonumber(opts.args))
	end, { force = true, nargs = 1 })

	_G.dotfiles_terminal_winbar = M.winbar
	_G.dotfiles_terminal_tab_click = M.click

	for id = 1, 9 do
		local tab_id = id
		vim.keymap.set({ "n", "t" }, "<leader>T" .. id, function()
			M.select(tab_id)
		end, { desc = "Select terminal tab " .. id })
	end
end

function M.new(opts)
	opts = type(opts) == "table" and opts or {}
	prune_invalid_tabs()
	local id = state.next_id
	state.next_id = state.next_id + 1

	local tab = {
		id = id,
		cwd = opts.cwd or vim.fn.getcwd(0),
		label = opts.label or shell_name(opts.cmd),
	}
	table.insert(state.tabs, tab)
	state.active = id
	hide_other_terminals(tab)

	local terminal_opts = {
		count = id,
		cwd = tab.cwd,
		auto_close = false,
	}
	if state.height then
		terminal_opts.win = { height = state.height }
	end

	local ok, terminal = pcall(function()
		return Snacks.terminal.open(opts.cmd, terminal_opts)
	end)

	if not ok then
		forget(id, false)
		local replacement = current_tab()
		if replacement then
			show(replacement)
		end
		error(terminal)
	end

	tab.terminal = terminal
	register_lifecycle(tab)
	redraw_winbars()
	return tab
end

function M.toggle()
	prune_invalid_tabs()
	local tab = current_tab()
	if not valid_tab(tab) then
		return M.new()
	end

	if terminal_visible_here(tab) then
		remember_height(tab)
		tab.terminal:hide()
	else
		show(tab)
	end
end

function M.select(id)
	prune_invalid_tabs()
	local index = tab_index(id)
	if index then
		show(state.tabs[index])
	end
end

local function cycle(delta)
	prune_invalid_tabs()
	if #state.tabs == 0 then
		return M.new()
	end

	local index = tab_index(state.active) or 1
	index = ((index - 1 + delta) % #state.tabs) + 1
	show(state.tabs[index])
end

function M.next()
	cycle(1)
end

function M.previous()
	cycle(-1)
end

function M.close(id)
	prune_invalid_tabs()
	id = id or state.active
	local index = tab_index(id)
	if not index then
		return
	end

	local tab = state.tabs[index]
	local reopen = terminal_visible(tab)
	remember_height(tab)
	forget(id, false)

	if tab.terminal then
		tab.terminal:close()
	end

	local replacement = current_tab()
	if reopen and replacement then
		vim.schedule(function()
			show(replacement)
		end)
	end
end

function M.winbar()
	local segments = { "%#TerminalTabFill# " }
	local suffix = winbar_focused() and "" or "Dim"

	for _, tab in ipairs(state.tabs) do
		local active = tab.id == state.active
		local body = (active and "TerminalTabActive" or "TerminalTabInactive") .. suffix
		local edge = (active and "TerminalTabActiveEdge" or "TerminalTabInactiveEdge") .. suffix
		local label = escape_statusline((" %d 󰆍 %s "):format(tab.id, tab_title(tab)))

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
		if button == "m" then
			M.close(id)
		else
			M.select(id)
		end
	end)
end

return M
