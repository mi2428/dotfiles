local M = {}

local sessions = {}
local pending_sessions = {}
local child_flag = "dotfiles_git_diff_peek_child"

local function replace_winhighlight(win, group, target)
	local entries = vim.split(vim.wo[win].winhighlight, ",", { plain = true, trimempty = true })
	local replacement = group .. ":" .. target
	local replaced = false
	for index, entry in ipairs(entries) do
		if vim.startswith(entry, group .. ":") then
			entries[index] = replacement
			replaced = true
			break
		end
	end
	if not replaced then
		entries[#entries + 1] = replacement
	end
	vim.wo[win].winhighlight = table.concat(entries, ",")
end

local function set_local_option(win, name, value)
	vim.api.nvim_set_option_value(name, value, { scope = "local", win = win })
end

local function refresh_minimap()
	local map = package.loaded["mini.map"]
	if map and map.refresh then
		pcall(map.refresh, {}, { layout = true, integrations = true, lines = true, scrollbar = true })
	end
end

local function attach_dropbar(win)
	if not win or not vim.api.nvim_win_is_valid(win) then
		return
	end
	local ok, bar = pcall(require, "dropbar.utils.bar")
	if ok and type(bar.attach) == "function" then
		pcall(bar.attach, vim.api.nvim_win_get_buf(win), win)
	end
end

function M.apply_editor_chrome(win, opts)
	opts = opts or {}
	if not win or not vim.api.nvim_win_is_valid(win) then
		return
	end
	if opts.popup_child then
		vim.w[win][child_flag] = true
		vim.w[win].dotfiles_git_diff_peek_role = opts.role
	end

	local buf = vim.api.nvim_win_get_buf(win)
	set_local_option(win, "foldcolumn", "1")
	if opts.foldlevel ~= nil then
		set_local_option(win, "foldlevel", opts.foldlevel)
	end
	set_local_option(win, "foldenable", true)
	set_local_option(win, "signcolumn", "no")
	set_local_option(win, "number", true)
	set_local_option(win, "relativenumber", true)
	set_local_option(win, "numberwidth", 3)
	set_local_option(
		win,
		"statuscolumn",
		opts.statuscolumn or vim.api.nvim_get_option_value("statuscolumn", { scope = "local", win = win })
	)
	if opts.winbar ~= nil then
		set_local_option(win, "winbar", opts.winbar)
	end

	vim.api.nvim_win_call(win, function()
		vim.opt_local.fillchars:append({ diff = " " })
		vim.wo.cursorline = true
		vim.wo.cursorlineopt = "number"
	end)
	replace_winhighlight(win, "Normal", "Normal")
	replace_winhighlight(win, "NormalNC", "NormalNC")
	replace_winhighlight(win, "WinBar", "WinBar")
	replace_winhighlight(win, "WinBarNC", "WinBarNC")
	vim.b[buf].dotfiles_disable_hlchunk = true

	if opts.minimap_disabled ~= nil then
		vim.w[win].dotfiles_disable_minimap = opts.minimap_disabled
	end
end

local function snapshot_editor_chrome(win)
	return {
		statuscolumn = vim.api.nvim_get_option_value("statuscolumn", { scope = "local", win = win }),
		winbar = vim.api.nvim_get_option_value("winbar", { scope = "local", win = win }),
	}
end

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

local function open_all_folds(session)
	for _, pane in ipairs(session.panes) do
		if pane:valid() then
			vim.api.nvim_win_call(pane.win, function()
				vim.cmd.normal({ args = { "zR" }, bang = true })
			end)
		end
	end
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
			add_buffer_map(session, buf, "zR", function()
				if pane_index(session, vim.api.nvim_get_current_win()) then
					open_all_folds(session)
				else
					vim.cmd.normal({ args = { "zR" }, bang = true })
				end
			end, "Open all Git diff folds")
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

local function open_layout(tab, source_win, source_buf, source_view, expand_all_folds)
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
	local source_chrome = snapshot_editor_chrome(source_win)
	local session = {
		maps = {},
		panes = {},
		underlay = {
			win = source_win,
			buf = source_buf,
			disable_minimap = vim.w[source_win].dotfiles_disable_minimap,
			disable_hlchunk = vim.b[source_buf].dotfiles_disable_hlchunk,
			underlay_flag = vim.w[source_win].dotfiles_git_diff_peek_underlay,
		},
	}
	local wins = {}
	local children = { box = "horizontal" }
	local source_pane
	local revision_wins = {}

	for index, win in ipairs(diff_wins) do
		local name = "pane_" .. index
		local buf = vim.api.nvim_win_get_buf(win)
		local role = win == source_win and "worktree" or "revision"
		local chrome = {
			popup_child = true,
			role = role,
			foldlevel = 0,
			minimap_disabled = role ~= "worktree",
			statuscolumn = source_chrome.statuscolumn,
			winbar = source_chrome.winbar ~= "" and source_chrome.winbar or "%{%v:lua.dropbar()%}",
		}
		local pane = snacks.win({
			show = false,
			buf = buf,
			minimal = false,
			backdrop = false,
			enter = false,
			keys = { q = false },
			w = {
				[child_flag] = true,
				dotfiles_git_diff_peek_role = role,
			},
			wo = {
				cursorbind = true,
				diff = true,
				foldenable = true,
				foldmethod = "diff",
				scrollbind = true,
			},
			on_win = function(child)
				local child_win = child.win
				if child_win and vim.api.nvim_win_is_valid(child_win) then
					M.apply_editor_chrome(child_win, chrome)
				end
			end,
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
				if vim.api.nvim_win_is_valid(session.underlay.win) then
					vim.w[session.underlay.win].dotfiles_git_diff_peek_underlay = session.underlay.underlay_flag
				end
				if vim.api.nvim_win_is_valid(session.underlay.win) then
					vim.w[session.underlay.win].dotfiles_disable_minimap = session.underlay.disable_minimap
				end
				if vim.api.nvim_buf_is_valid(session.underlay.buf) then
					vim.b[session.underlay.buf].dotfiles_disable_hlchunk = session.underlay.disable_hlchunk
				end
				if
					vim.api.nvim_win_is_valid(source_win)
					and vim.api.nvim_win_get_tabpage(source_win) == vim.api.nvim_get_current_tabpage()
				then
					vim.api.nvim_set_current_win(source_win)
				end
				refresh_minimap()
			end)
		end,
	})
	session.layout = layout
	sessions[tab] = session
	-- Floating windows inherit local options from the current window. Take the
	-- editor out of diff mode before Snacks creates the non-content layout root.
	vim.wo[source_win].diff = false
	vim.w[source_win].dotfiles_git_diff_peek_underlay = true
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
	for _, pane in ipairs(session.panes) do
		if vim.api.nvim_win_is_valid(pane.win) then
			local chrome = {
				popup_child = true,
				role = vim.w[pane.win].dotfiles_git_diff_peek_role,
				minimap_disabled = vim.w[pane.win].dotfiles_git_diff_peek_role ~= "worktree",
				statuscolumn = source_chrome.statuscolumn,
				winbar = source_chrome.winbar ~= "" and source_chrome.winbar or "%{%v:lua.dropbar()%}",
			}
			M.apply_editor_chrome(pane.win, chrome)
			attach_dropbar(pane.win)
		end
	end
	refresh_minimap()
	install_buffer_maps(session)
	if expand_all_folds then
		open_all_folds(session)
	end
end

function M.toggle()
	local tab = vim.api.nvim_get_current_tabpage()
	local session = session_for_tab(tab)
	if session then
		session.layout:close()
		return
	end
	local pending = pending_sessions[tab]
	if pending then
		pending.cancelled = true
		pending.maps = remove_buffer_maps(pending)
		pending_sessions[tab] = nil
		close_regular_diff(tab)
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
	pending = {
		cancelled = false,
		expand_all_folds = false,
		maps = {},
		tab = tab,
	}
	pending_sessions[tab] = pending
	add_buffer_map(pending, source_buf, "zR", function()
		pending.expand_all_folds = true
		vim.cmd.normal({ args = { "zR" }, bang = true })
	end, "Open pending Git diff folds")
	local ok, diff_error = pcall(require("gitsigns").diffthis, nil, { vertical = true }, function(err)
		pending.maps = remove_buffer_maps(pending)
		if pending_sessions[tab] ~= pending or pending.cancelled then
			close_regular_diff(tab)
			return
		end
		pending_sessions[tab] = nil
		if err then
			vim.notify(tostring(err), vim.log.levels.ERROR)
			return
		end
		open_layout(tab, source_win, source_buf, source_view, pending.expand_all_folds)
	end)
	if not ok then
		pending.maps = remove_buffer_maps(pending)
		if pending_sessions[tab] == pending then
			pending_sessions[tab] = nil
		end
		vim.notify(tostring(diff_error), vim.log.levels.ERROR)
	end
end

return M
