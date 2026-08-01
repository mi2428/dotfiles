local M = {}

local sessions = {}
local pending_sessions = {}
local child_flag = "dotfiles_git_diff_peek_child"
local revision_winbar = "%{%v:lua.require('config.git_diff_peek').revision_winbar()%}"

local function statusline_hl(group, text)
	return ("%%#%s#%s%%*"):format(group, text:gsub("%%", "%%%%"))
end

local function revision_breadcrumb(source_name, revision_name, active)
	local basename = vim.fs.basename(source_name)
	local tail = revision_name:match("//([^/]*)$") or ""
	local revision = vim.endswith(tail, basename) and tail:sub(1, #tail - #basename) or ":0:"
	if revision == "" then
		revision = ":0:"
	end
	local suffix = active and "" or "NC"
	local file_icon, file_icon_hl = "󰈔 ", "DropBarIconKindFile" .. suffix
	local ok, devicons = pcall(require, "nvim-web-devicons")
	if ok then
		local icon, icon_hl = devicons.get_icon(basename, vim.fn.fnamemodify(basename, ":e"), { default = true })
		if icon then
			file_icon = icon .. " "
			file_icon_hl = icon_hl or file_icon_hl
		end
	end
	local separator = statusline_hl("DropBarIconUISeparator" .. suffix, "  ")
	return " "
		.. statusline_hl("DropBarIconKindFolder" .. suffix, "󰉋 ")
		.. statusline_hl("DropBarKindDir" .. suffix, ".git")
		.. separator
		.. "󰈔 "
		.. statusline_hl("DropBarKindFile" .. suffix, revision)
		.. separator
		.. statusline_hl(file_icon_hl, file_icon)
		.. statusline_hl("DropBarKindFile" .. suffix, basename)
		.. " "
end

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

local function set_window_buffer_keepalt(win, buf)
	vim.api.nvim_win_call(win, function()
		vim.cmd({ cmd = "buffer", args = { tostring(buf) }, mods = { hide = true, keepalt = true } })
	end)
end

local function create_underlay_scratch()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].swapfile = false
	vim.bo[buf].undolevels = -1
	vim.bo[buf].modifiable = false
	return buf
end

local function restore_underlay(session)
	local underlay = session.underlay
	if underlay.restored then
		return
	end
	underlay.restored = true

	if vim.api.nvim_win_is_valid(underlay.win) then
		if
			underlay.scratch
			and vim.api.nvim_buf_is_valid(underlay.scratch)
			and vim.api.nvim_win_get_buf(underlay.win) == underlay.scratch
			and vim.api.nvim_buf_is_valid(underlay.buf)
		then
			local restored = pcall(set_window_buffer_keepalt, underlay.win, underlay.buf)
			if restored then
				pcall(vim.api.nvim_win_call, underlay.win, function()
					vim.fn.winrestview(underlay.view)
				end)
			end
		end
		vim.w[underlay.win].dotfiles_git_diff_peek_underlay = underlay.underlay_flag
		vim.w[underlay.win].dotfiles_disable_minimap = underlay.disable_minimap
	end
	if vim.api.nvim_buf_is_valid(underlay.buf) then
		vim.b[underlay.buf].dotfiles_disable_hlchunk = underlay.disable_hlchunk
	end
	if
		underlay.scratch
		and vim.api.nvim_buf_is_valid(underlay.scratch)
		and #vim.fn.win_findbuf(underlay.scratch) == 0
	then
		pcall(vim.api.nvim_buf_delete, underlay.scratch, { force = true })
	end
end

local function suppress_background_minimaps(session, tab)
	session.background_minimap_flags = session.background_minimap_flags or {}
	local changed = false
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
		local buf = vim.api.nvim_win_get_buf(win)
		if
			win ~= session.underlay.win
			and vim.api.nvim_win_get_config(win).relative == ""
			and vim.w[win][child_flag] ~= true
			and vim.bo[buf].buftype == ""
			and session.background_minimap_flags[win] == nil
		then
			session.background_minimap_flags[win] = { value = vim.w[win].dotfiles_disable_minimap }
			if vim.w[win].dotfiles_disable_minimap ~= true then
				vim.w[win].dotfiles_disable_minimap = true
				changed = true
			end
		end
	end
	return changed
end

local function stop_background_minimap_monitor(session)
	if session.background_minimap_autocmd then
		pcall(vim.api.nvim_del_autocmd, session.background_minimap_autocmd)
		session.background_minimap_autocmd = nil
	end
end

local function start_background_minimap_monitor(session, tab)
	session.background_minimap_autocmd = vim.api.nvim_create_autocmd({ "WinNew", "BufWinEnter" }, {
		desc = "Git diff peek background minimap ownership",
		callback = function()
			if session.background_minimap_scan_scheduled then
				return
			end
			session.background_minimap_scan_scheduled = true
			vim.schedule(function()
				session.background_minimap_scan_scheduled = false
				if session.cleanup_scheduled or sessions[tab] ~= session or not vim.api.nvim_tabpage_is_valid(tab) then
					return
				end
				if suppress_background_minimaps(session, tab) then
					refresh_minimap()
				end
			end)
		end,
	})
end

local function restore_background_minimaps(session)
	for win, state in pairs(session.background_minimap_flags or {}) do
		if vim.api.nvim_win_is_valid(win) then
			vim.w[win].dotfiles_disable_minimap = state.value
		end
	end
	session.background_minimap_flags = {}
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

function M.source_filetype(buf)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	local filetype = vim.bo[buf].filetype
	if filetype ~= "" and filetype ~= "bigfile" then
		return filetype
	end
	local name = vim.api.nvim_buf_get_name(buf)
	local inferred = name ~= "" and vim.filetype.match({ filename = name }) or nil
	if inferred and inferred ~= "" and inferred ~= "bigfile" then
		return inferred
	end
	local syntax = vim.bo[buf].syntax
	if syntax ~= "" and syntax ~= "bigfile" then
		return syntax
	end
end

function M.prepare_revision_buffer(buf, source_buf)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	local filetype = vim.b[buf].dotfiles_git_diff_peek_source_filetype or (source_buf and M.source_filetype(source_buf))
	local syntax = vim.b[buf].dotfiles_git_diff_peek_source_syntax
		or (source_buf and vim.api.nvim_buf_is_valid(source_buf) and vim.bo[source_buf].syntax)
	if not filetype or filetype == "" then
		return
	end
	vim.b[buf].dotfiles_git_diff_peek_source_filetype = filetype
	vim.b[buf].dotfiles_git_diff_peek_source_syntax = syntax
	if vim.bo[buf].filetype ~= filetype then
		pcall(vim.treesitter.stop, buf)
		vim.api.nvim_buf_call(buf, function()
			vim.cmd({ cmd = "setlocal", args = { "filetype=" .. filetype }, mods = { noautocmd = true } })
		end)
	end
	local lang_ok, lang = pcall(vim.treesitter.language.get_lang, filetype)
	local started = lang_ok and lang and pcall(vim.treesitter.start, buf, lang)
	if started then
		vim.bo[buf].syntax = ""
	elseif syntax and syntax ~= "" and syntax ~= "bigfile" then
		vim.bo[buf].syntax = syntax
	end
end

function M.revision_winbar()
	local win = tonumber(vim.g.statusline_winid) or vim.api.nvim_get_current_win()
	if not vim.api.nvim_win_is_valid(win) then
		return ""
	end
	local breadcrumb = vim.w[win].dotfiles_git_diff_peek_breadcrumb
	if type(breadcrumb) ~= "table" then
		return breadcrumb or ""
	end
	return breadcrumb[breadcrumb.focused and "active" or "inactive"] or ""
end

local function refresh_revision_breadcrumb_focus()
	local current_win = vim.api.nvim_get_current_win()
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local breadcrumb = vim.w[win].dotfiles_git_diff_peek_breadcrumb
		if type(breadcrumb) == "table" then
			local focused = win == current_win
			if breadcrumb.focused ~= focused then
				breadcrumb.focused = focused
				vim.w[win].dotfiles_git_diff_peek_breadcrumb = breadcrumb
			end
		end
	end
end

vim.api.nvim_create_autocmd("WinEnter", {
	group = vim.api.nvim_create_augroup("dotfiles-git-diff-peek-breadcrumb-focus", { clear = true }),
	callback = refresh_revision_breadcrumb_focus,
})

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
	local role = opts.role or vim.w[win].dotfiles_git_diff_peek_role
	if role == "revision" and vim.b[buf].dotfiles_git_diff_peek_source_filetype then
		M.prepare_revision_buffer(buf)
	end
	set_local_option(win, "foldcolumn", "1")
	if opts.foldlevel ~= nil then
		set_local_option(win, "foldlevel", opts.foldlevel)
	end
	set_local_option(win, "foldenable", true)
	set_local_option(win, "foldmethod", "diff")
	set_local_option(win, "signcolumn", "no")
	set_local_option(win, "number", true)
	set_local_option(win, "relativenumber", true)
	set_local_option(win, "numberwidth", 3)
	set_local_option(win, "wrap", true)
	local statuscolumn = opts.statuscolumn
	if statuscolumn == nil then
		statuscolumn = vim.api.nvim_get_option_value("statuscolumn", { scope = "local", win = win })
		if statuscolumn == "" then
			statuscolumn = vim.go.statuscolumn
		end
	end
	local suppress_statuscolumn = vim.bo[buf].filetype == "bigfile" and role ~= "revision"
	set_local_option(win, "statuscolumn", suppress_statuscolumn and "" or statuscolumn)
	if role == "revision" and vim.w[win].dotfiles_git_diff_peek_breadcrumb then
		set_local_option(win, "winbar", revision_winbar)
	elseif opts.winbar ~= nil then
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
	local statuscolumn = vim.api.nvim_get_option_value("statuscolumn", { scope = "local", win = win })
	return {
		statuscolumn = statuscolumn ~= "" and statuscolumn or vim.go.statuscolumn,
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

local function cleanup_session(tab, session, focus_underlay)
	if session.cleanup_scheduled then
		return
	end
	session.cleanup_scheduled = true
	stop_background_minimap_monitor(session)
	if sessions[tab] == session then
		sessions[tab] = nil
	end
	session.maps = remove_buffer_maps(session)
	vim.schedule(function()
		restore_underlay(session)
		restore_background_minimaps(session)
		if
			focus_underlay
			and vim.api.nvim_win_is_valid(session.underlay.win)
			and vim.api.nvim_win_get_tabpage(session.underlay.win) == vim.api.nvim_get_current_tabpage()
		then
			vim.api.nvim_set_current_win(session.underlay.win)
		end
		refresh_minimap()
	end)
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
		local left_revision = is_gitsigns_revision(left)
		local right_revision = is_gitsigns_revision(right)
		if left_revision ~= right_revision then
			return left_revision
		end
		local left_pos = vim.api.nvim_win_get_position(left)
		local right_pos = vim.api.nvim_win_get_position(right)
		return left_pos[2] == right_pos[2] and left_pos[1] < right_pos[1] or left_pos[2] < right_pos[2]
	end)
	return wins
end

local function open_layout(tab, source, expand_all_folds)
	local source_win = source.win
	local source_buf = source.buf
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
		close_regular_diff(tab)
		vim.notify("No Git revision available for this buffer", vim.log.levels.INFO)
		return
	end

	local snacks = require("snacks")
	local source_chrome = source.chrome
	local session = {
		maps = {},
		panes = {},
		underlay = source,
	}
	local wins = {}
	local children = { box = "horizontal" }
	local source_pane
	local revision_wins = {}
	local function apply_pane_chrome(win, role, initialize_folds)
		if not win or not vim.api.nvim_win_is_valid(win) then
			return
		end
		local buf = vim.api.nvim_win_get_buf(win)
		if role == "revision" then
			M.prepare_revision_buffer(buf, source_buf)
			local source_name = vim.api.nvim_buf_get_name(source_buf)
			local revision_name = vim.api.nvim_buf_get_name(buf)
			vim.w[win].dotfiles_git_diff_peek_breadcrumb = {
				active = revision_breadcrumb(source_name, revision_name, true),
				inactive = revision_breadcrumb(source_name, revision_name, false),
				focused = win == vim.api.nvim_get_current_win(),
			}
		end
		M.apply_editor_chrome(win, {
			popup_child = true,
			role = role,
			foldlevel = initialize_folds and 0 or nil,
			minimap_disabled = role ~= "worktree",
			statuscolumn = source_chrome.statuscolumn,
			winbar = source_chrome.winbar ~= "" and source_chrome.winbar or "%{%v:lua.dropbar()%}",
		})
		if role == "worktree" then
			attach_dropbar(win)
		end
	end

	for index, win in ipairs(diff_wins) do
		local name = "pane_" .. index
		local buf = vim.api.nvim_win_get_buf(win)
		local role = win == source_win and "worktree" or "revision"
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
				apply_pane_chrome(child.win, role, true)
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
			height = 0.9,
			min_width = 160,
			max_width = 300,
			border = "rounded",
			title = " Git Diff Peek ",
			title_pos = "center",
			children,
		},
		on_close = function()
			cleanup_session(tab, session, true)
		end,
	})
	session.layout = layout

	local ok, layout_error = xpcall(function()
		sessions[tab] = session
		suppress_background_minimaps(session, tab)
		-- Floating windows inherit local options from the current window. Take the
		-- editor out of diff mode and detach its large buffer before Snacks creates
		-- the non-content layout root.
		if not vim.api.nvim_win_is_valid(source_win) or vim.api.nvim_win_get_buf(source_win) ~= source_buf then
			error("Git diff peek source window changed while opening")
		end
		vim.wo[source_win].diff = false
		session.underlay.scratch = create_underlay_scratch()
		vim.w[source_win].dotfiles_git_diff_peek_underlay = true
		set_window_buffer_keepalt(source_win, session.underlay.scratch)
		layout:show()

		for _, win in ipairs(revision_wins) do
			if vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_close(win, true)
			end
		end
		if source_pane and source_pane:valid() then
			source_pane:focus()
			vim.api.nvim_win_call(source_pane.win, function()
				vim.fn.winrestview(source.view)
			end)
		end
		for _, pane in ipairs(session.panes) do
			if vim.api.nvim_win_is_valid(pane.win) then
				apply_pane_chrome(pane.win, vim.w[pane.win].dotfiles_git_diff_peek_role, false)
			end
		end
		refresh_minimap()
		vim.schedule(function()
			if sessions[tab] ~= session or not session.layout or not session.layout:valid() then
				return
			end
			for _, pane in ipairs(session.panes) do
				if pane.win and vim.api.nvim_win_is_valid(pane.win) then
					apply_pane_chrome(pane.win, vim.w[pane.win].dotfiles_git_diff_peek_role, false)
				end
			end
			refresh_minimap()
		end)
		install_buffer_maps(session)
		start_background_minimap_monitor(session, tab)
		if expand_all_folds then
			open_all_folds(session)
		end
	end, debug.traceback)

	if not ok then
		if session.layout then
			pcall(function()
				session.layout:close()
			end)
		end
		cleanup_session(tab, session, true)
		close_regular_diff(tab)
		vim.notify(tostring(layout_error), vim.log.levels.ERROR)
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
	local source = {
		win = source_win,
		buf = source_buf,
		view = vim.fn.winsaveview(),
		chrome = snapshot_editor_chrome(source_win),
		disable_minimap = vim.w[source_win].dotfiles_disable_minimap,
		disable_hlchunk = vim.b[source_buf].dotfiles_disable_hlchunk,
		underlay_flag = vim.w[source_win].dotfiles_git_diff_peek_underlay,
	}
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
			close_regular_diff(tab)
			vim.notify(tostring(err), vim.log.levels.ERROR)
			return
		end
		local opened, open_error = xpcall(function()
			open_layout(tab, source, pending.expand_all_folds)
		end, debug.traceback)
		if not opened then
			close_regular_diff(tab)
			vim.notify(tostring(open_error), vim.log.levels.ERROR)
		end
	end)
	if not ok then
		pending.maps = remove_buffer_maps(pending)
		if pending_sessions[tab] == pending then
			pending_sessions[tab] = nil
		end
		close_regular_diff(tab)
		vim.notify(tostring(diff_error), vim.log.levels.ERROR)
	end
end

return M
