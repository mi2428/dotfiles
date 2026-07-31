local M = {}

local sessions = {}

local function is_gitsigns_revision(win)
	local buf = vim.api.nvim_win_get_buf(win)
	return vim.startswith(vim.api.nvim_buf_get_name(buf), "gitsigns://")
end

local function session_for_tab(tab)
	local session = sessions[tab]
	if session and session.layout and session.layout:valid() then
		return session
	end
	sessions[tab] = nil
	return nil
end

local function close_regular_diff(tab)
	local revision_wins = {}
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
		if vim.wo[win].diff and is_gitsigns_revision(win) then
			revision_wins[#revision_wins + 1] = win
		end
	end
	if #revision_wins == 0 then
		return false
	end

	for _, win in ipairs(revision_wins) do
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
		if vim.wo[win].diff then
			vim.wo[win].diff = false
		end
	end
	return true
end

local function pane_index(session, win)
	for index, pane in ipairs(session.panes) do
		if pane.win == win then
			return index
		end
	end
end

local function focus_pane(session, offset)
	local index = pane_index(session, vim.api.nvim_get_current_win())
	if not index then
		return false
	end
	local target = session.panes[((index - 1 + offset) % #session.panes) + 1]
	if target and target:valid() then
		target:focus()
	end
	return true
end

local function has_buffer_map(buf, lhs)
	local key = vim.keycode(lhs)
	return vim.iter(vim.api.nvim_buf_get_keymap(buf, "n")):any(function(mapping)
		return vim.keycode(mapping.lhs) == key
	end)
end

local function add_buffer_map(session, buf, lhs, callback, desc)
	if has_buffer_map(buf, lhs) then
		return
	end
	vim.keymap.set("n", lhs, callback, { buffer = buf, desc = desc, nowait = true })
	session.maps[#session.maps + 1] = { buf = buf, lhs = lhs, desc = desc }
end

local function remove_buffer_maps(session)
	for _, mapping in ipairs(session.maps) do
		if vim.api.nvim_buf_is_valid(mapping.buf) then
			local current = vim.iter(vim.api.nvim_buf_get_keymap(mapping.buf, "n")):find(function(candidate)
				return vim.keycode(candidate.lhs) == vim.keycode(mapping.lhs)
			end)
			if current and current.desc == mapping.desc then
				pcall(vim.keymap.del, "n", mapping.lhs, { buffer = mapping.buf })
			end
		end
	end
	return {}
end

local function install_buffer_maps(session)
	local seen = {}
	for _, pane in ipairs(session.panes) do
		local buf = pane.buf
		if not seen[buf] then
			seen[buf] = true
			add_buffer_map(session, buf, "q", function()
				if pane_index(session, vim.api.nvim_get_current_win()) then
					session.layout:close()
				else
					vim.api.nvim_feedkeys("q", "n", false)
				end
			end, "Close Git diff peek")
			add_buffer_map(session, buf, "<C-w>h", function()
				if not focus_pane(session, -1) then
					vim.cmd.wincmd("h")
				end
			end, "Move to previous Git diff pane")
			add_buffer_map(session, buf, "<C-w>l", function()
				if not focus_pane(session, 1) then
					vim.cmd.wincmd("l")
				end
			end, "Move to next Git diff pane")
			add_buffer_map(session, buf, "<C-w>w", function()
				if not focus_pane(session, 1) then
					vim.cmd.wincmd("w")
				end
			end, "Cycle Git diff panes")
		end
	end
end

local function sorted_diff_windows(tab, source_win, source_buf)
	local wins = vim.tbl_filter(function(win)
		return vim.wo[win].diff
			and (win == source_win or vim.api.nvim_win_get_buf(win) == source_buf or is_gitsigns_revision(win))
	end, vim.api.nvim_tabpage_list_wins(tab))
	table.sort(wins, function(left, right)
		local left_pos = vim.api.nvim_win_get_position(left)
		local right_pos = vim.api.nvim_win_get_position(right)
		return left_pos[2] == right_pos[2] and left_pos[1] < right_pos[1] or left_pos[2] < right_pos[2]
	end)
	return wins
end

local function open_layout(tab, source_win, source_buf, source_view)
	if
		vim.api.nvim_get_current_tabpage() ~= tab
		or not vim.api.nvim_win_is_valid(source_win)
		or vim.api.nvim_win_get_buf(source_win) ~= source_buf
	then
		close_regular_diff(tab)
		return
	end

	local diff_wins = sorted_diff_windows(tab, source_win, source_buf)
	if #diff_wins < 2 then
		vim.wo[source_win].diff = false
		vim.notify("No Git revision available for this buffer", vim.log.levels.INFO)
		return
	end

	local snacks = require("snacks")
	local session = {
		maps = {},
		panes = {},
	}
	local wins = {}
	local children = { box = "horizontal" }
	local source_pane
	local revision_wins = {}

	for index, win in ipairs(diff_wins) do
		local name = "pane_" .. index
		local buf = vim.api.nvim_win_get_buf(win)
		local pane = snacks.win({
			show = false,
			buf = buf,
			minimal = false,
			backdrop = false,
			enter = false,
			keys = { q = false },
			wo = {
				cursorbind = true,
				diff = true,
				foldenable = true,
				foldmethod = "diff",
				scrollbind = true,
			},
		})
		wins[name] = pane
		children[#children + 1] = {
			win = name,
			border = index == 1 and "none" or "left",
		}
		session.panes[#session.panes + 1] = pane
		if win == source_win then
			source_pane = pane
		else
			revision_wins[#revision_wins + 1] = win
		end
	end

	local layout = snacks.layout.new({
		show = false,
		wins = wins,
		layout = {
			box = "vertical",
			width = 0.9,
			height = 0.85,
			border = "rounded",
			title = " Git Diff Peek ",
			title_pos = "center",
			children,
		},
		on_close = function()
			if sessions[tab] == session then
				sessions[tab] = nil
			end
			session.maps = remove_buffer_maps(session)
			vim.schedule(function()
				if
					vim.api.nvim_win_is_valid(source_win)
					and vim.api.nvim_win_get_tabpage(source_win) == vim.api.nvim_get_current_tabpage()
				then
					vim.api.nvim_set_current_win(source_win)
				end
			end)
		end,
	})
	session.layout = layout
	sessions[tab] = session
	-- Floating windows inherit local options from the current window. Take the
	-- editor out of diff mode before Snacks creates the non-content layout root.
	vim.wo[source_win].diff = false
	layout:show()

	for _, win in ipairs(revision_wins) do
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end
	if source_pane and source_pane:valid() then
		source_pane:focus()
		vim.api.nvim_win_call(source_pane.win, function()
			vim.fn.winrestview(source_view)
		end)
	end
	install_buffer_maps(session)
end

function M.toggle()
	local tab = vim.api.nvim_get_current_tabpage()
	local session = session_for_tab(tab)
	if session then
		session.layout:close()
		return
	end
	if close_regular_diff(tab) then
		return
	end
	if vim.wo.diff then
		vim.notify("Already in a non-Gitsigns diff view", vim.log.levels.INFO)
		return
	end

	local source_win = vim.api.nvim_get_current_win()
	local source_buf = vim.api.nvim_get_current_buf()
	local source_view = vim.fn.winsaveview()
	require("gitsigns").diffthis(nil, { vertical = true }, function(err)
		if err then
			vim.notify(tostring(err), vim.log.levels.ERROR)
			return
		end
		open_layout(tab, source_win, source_buf, source_view)
	end)
end

return M
