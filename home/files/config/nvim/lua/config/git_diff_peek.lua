local M = {}

local sessions = {}
local pending_sessions = {}
local child_flag = "dotfiles_git_diff_peek_child"
local cover_flag = "dotfiles_git_diff_peek_cover"
local revision_winbar = "%{%v:lua.require('config.git_diff_peek').revision_winbar()%}"
local underlay_hl_ns = vim.api.nvim_create_namespace("dotfiles-git-diff-peek-underlay")
local statusline_owners = 0
local saved_laststatus
local underlay_option_names = {
	"colorcolumn",
	"cursorcolumn",
	"cursorline",
	"fillchars",
	"foldcolumn",
	"list",
	"number",
	"relativenumber",
	"signcolumn",
	"statuscolumn",
	"statusline",
	"winbar",
}

for _, group in ipairs({
	"Normal",
	"NormalNC",
	"EndOfBuffer",
	"StatusLine",
	"StatusLineNC",
	"WinBar",
	"WinBarNC",
	"WinSeparator",
	"VertSplit",
}) do
	vim.api.nvim_set_hl(underlay_hl_ns, group, { fg = "NONE", bg = "NONE", nocombine = true })
end

local function visible_tabline_height()
	return (vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1)) and 1 or 0
end

local function acquire_global_statusline()
	if statusline_owners == 0 then
		saved_laststatus = vim.o.laststatus
	end
	statusline_owners = statusline_owners + 1
	vim.o.laststatus = 3
	return { released = false }
end

local function release_global_statusline(guard)
	if not guard or guard.released then
		return
	end
	guard.released = true
	statusline_owners = math.max(0, statusline_owners - 1)
	if statusline_owners == 0 then
		if saved_laststatus ~= nil then
			vim.o.laststatus = saved_laststatus
		end
		saved_laststatus = nil
	end
end

local function capture_screen_line(row, width)
	local cells = {}
	local col = 1
	while col <= width do
		local char = vim.fn.screenstring(row, col)
		if char == "" then
			char = " "
		end
		cells[#cells + 1] = char
		col = col + math.max(1, vim.fn.strdisplaywidth(char))
	end
	return table.concat(cells)
end

local function capture_frozen_screen()
	vim.cmd.redraw({ bang = true })
	local top = visible_tabline_height()
	local height = math.max(1, vim.o.lines - top - 1)
	local lines = {}
	for offset = 1, height do
		lines[offset] = capture_screen_line(top + offset, vim.o.columns)
	end
	return {
		height = height,
		lines = lines,
		top = top,
		width = vim.o.columns,
	}
end

local function fit_screen_line(line, width)
	local cells = {}
	local used = 0
	for index = 0, vim.fn.strchars(line) - 1 do
		local char = vim.fn.strcharpart(line, index, 1)
		local char_width = math.max(1, vim.fn.strdisplaywidth(char))
		if used + char_width > width then
			break
		end
		cells[#cells + 1] = char
		used = used + char_width
	end
	if used < width then
		cells[#cells + 1] = string.rep(" ", width - used)
	end
	return table.concat(cells)
end

local function frozen_highlights()
	local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
	local comment = vim.api.nvim_get_hl(0, { name = "Comment", link = false })
	local normal_nc = vim.api.nvim_get_hl(0, { name = "NormalNC", link = false })
	local attributes = {
		bg = normal.bg or normal_nc.bg,
		fg = comment.fg or normal_nc.fg or normal.fg,
		nocombine = true,
	}
	vim.api.nvim_set_hl(0, "DotfilesGitDiffPeekFrozen", attributes)
	vim.api.nvim_set_hl(0, "DotfilesGitDiffPeekFrozenEob", attributes)
end

local function render_frozen_screen(session)
	local cover = session.layout and session.layout.root and session.layout.root.backdrop
	if not cover or not cover:valid() then
		return
	end
	local config = vim.api.nvim_win_get_config(cover.win)
	local lines = {}
	for index = 1, config.height do
		lines[index] = fit_screen_line(session.snapshot.lines[index] or "", config.width)
	end
	frozen_highlights()
	vim.bo[cover.buf].modifiable = true
	vim.api.nvim_buf_set_lines(cover.buf, 0, -1, false, lines)
	vim.bo[cover.buf].modifiable = false
	vim.wo[cover.win].winhighlight = table.concat({
		"Normal:DotfilesGitDiffPeekFrozen",
		"NormalNC:DotfilesGitDiffPeekFrozen",
		"EndOfBuffer:DotfilesGitDiffPeekFrozenEob",
	}, ",")
end

local function stop_snapshot_resize_monitor(session)
	if session.snapshot_resize_autocmd then
		pcall(vim.api.nvim_del_autocmd, session.snapshot_resize_autocmd)
		session.snapshot_resize_autocmd = nil
	end
end

local function start_snapshot_resize_monitor(session, tab)
	session.snapshot_resize_autocmd = vim.api.nvim_create_autocmd("VimResized", {
		desc = "Git diff peek frozen background resize",
		callback = function()
			vim.schedule(function()
				if sessions[tab] == session and session.layout and session.layout:valid() then
					render_frozen_screen(session)
				end
			end)
		end,
	})
end

local function cover_backdrop()
	return {
		blend = 0,
		transparent = false,
		win = {
			row = visible_tabline_height,
			col = 0,
			width = function()
				return vim.o.columns
			end,
			height = function()
				return math.max(1, vim.o.lines - visible_tabline_height() - 1)
			end,
			focusable = false,
			noautocmd = true,
			wo = {
				colorcolumn = "",
				cursorcolumn = false,
				cursorline = false,
				fillchars = "eob: ",
				foldcolumn = "0",
				list = false,
				number = false,
				relativenumber = false,
				signcolumn = "no",
				statuscolumn = "",
				statusline = "",
				winbar = "",
				winblend = 0,
			},
			bo = {
				bufhidden = "wipe",
				buftype = "nofile",
				filetype = "git_diff_peek_snapshot",
				modifiable = false,
				swapfile = false,
				undolevels = -1,
			},
			w = {
				[cover_flag] = true,
			},
		},
	}
end

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

local default_cursorline_targets = {
	CursorLine = "DotfilesCursorLineDefault",
	CursorLineSign = "DotfilesCursorLineSignDefault",
	CursorLineFold = "DotfilesCursorLineFoldDefault",
	DotfilesCursorLineFoldOpen = "DotfilesCursorLineFoldOpenDefault",
	DotfilesCursorLineFoldClosed = "DotfilesCursorLineFoldClosedDefault",
	DotfilesCursorLineFoldDepth = "DotfilesCursorLineFoldDepthDefault",
	CursorLineNr = "DotfilesCursorLineNrDefault",
	DotfilesStatuscolumnMarker = "DotfilesStatuscolumnMarkerDefault",
	DotfilesCursorLineCodexNr = "DotfilesCursorLineCodexNrDefault",
}

local function ensure_default_cursorline_targets(win)
	local targets = {}
	for entry in vim.wo[win].winhighlight:gmatch("[^,]+") do
		local source, target = entry:match("^([^:]+):(.+)$")
		if source then
			targets[source] = target
		end
	end

	for source, target in pairs(default_cursorline_targets) do
		if targets[source] == nil or targets[source] == source then
			local attributes = vim.api.nvim_get_hl(0, { name = target, link = false })
			if next(attributes) ~= nil then
				replace_winhighlight(win, source, target)
			end
		end
	end
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

local function active_minimap_width(tab)
	local map = package.loaded["mini.map"]
	local manager = map and map._dotfiles_multi_window_manager
	if not map or not manager or manager.enabled ~= true then
		return 0
	end
	local map_win = map.current and map.current.win_data and map.current.win_data[tab]
	if map_win and vim.api.nvim_win_is_valid(map_win) then
		return vim.api.nvim_win_get_width(map_win)
	end
	local options = map.current and map.current.opts
	if not options or not next(options) then
		options = map.config
	end
	return math.max(0, tonumber(options and options.window and options.window.width) or 0)
end

local function inherit_minimap_margin(child, parent)
	local map = package.loaded["mini.map"]
	local manager = map and map._dotfiles_multi_window_manager
	if manager and type(manager.inherit_source_margin) == "function" then
		pcall(manager.inherit_source_margin, child, parent)
	end
end

local function prepare_minimap_margin_transfer(parent)
	local map = package.loaded["mini.map"]
	local manager = map and map._dotfiles_multi_window_manager
	if manager and type(manager.prepare_source_margin_transfer) == "function" then
		pcall(manager.prepare_source_margin_transfer, parent)
	end
end

local function discard_minimap_margin_transfer(parent)
	local map = package.loaded["mini.map"]
	local manager = map and map._dotfiles_multi_window_manager
	if manager and type(manager.discard_source_margin_transfer) == "function" then
		pcall(manager.discard_source_margin_transfer, parent)
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

local function snapshot_underlay_appearance(win)
	local options = {}
	for _, name in ipairs(underlay_option_names) do
		options[name] = vim.api.nvim_get_option_value(name, { scope = "local", win = win })
	end
	return {
		hl_ns = vim.api.nvim_get_hl_ns({ winid = win }),
		options = options,
	}
end

local function suppress_underlay(underlay)
	local win = underlay.win
	if not vim.api.nvim_win_is_valid(win) then
		return
	end
	set_local_option(win, "number", false)
	set_local_option(win, "relativenumber", false)
	set_local_option(win, "statuscolumn", "")
	set_local_option(win, "foldcolumn", "0")
	set_local_option(win, "signcolumn", "no")
	set_local_option(win, "cursorline", false)
	set_local_option(win, "cursorcolumn", false)
	set_local_option(win, "list", false)
	set_local_option(win, "colorcolumn", "")
	set_local_option(win, "winbar", " ")
	set_local_option(win, "statusline", " ")
	vim.api.nvim_win_call(win, function()
		vim.opt_local.fillchars:append({ eob = " " })
	end)
	vim.api.nvim_win_set_hl_ns(win, underlay_hl_ns)
end

local function restore_underlay_appearance(underlay, restored_source)
	local win = underlay.win
	if not vim.api.nvim_win_is_valid(win) then
		return
	end
	for _, name in ipairs(underlay_option_names) do
		pcall(set_local_option, win, name, underlay.appearance.options[name])
	end
	pcall(vim.api.nvim_win_set_hl_ns, win, underlay.appearance.hl_ns)
	if restored_source and vim.api.nvim_win_get_buf(win) == underlay.buf then
		pcall(vim.api.nvim_win_call, win, function()
			vim.fn.winrestview(underlay.view)
		end)
	end
end

local function restore_underlay(session)
	local underlay = session.underlay
	if underlay.restored then
		return false
	end
	underlay.restored = true

	local restored_source = false
	if vim.api.nvim_win_is_valid(underlay.win) then
		if
			underlay.scratch
			and vim.api.nvim_buf_is_valid(underlay.scratch)
			and vim.api.nvim_win_get_buf(underlay.win) == underlay.scratch
			and vim.api.nvim_buf_is_valid(underlay.buf)
		then
			restored_source = pcall(set_window_buffer_keepalt, underlay.win, underlay.buf)
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
	return restored_source
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
		-- Start conservatively until git.lua classifies the current row. Ordinary
		-- lines switch to "both"; changed lines keep Diffview's background and
		-- expose the mode only through the number/rail foregrounds.
		vim.wo.cursorlineopt = "number"
	end)
	replace_winhighlight(win, "Normal", "Normal")
	replace_winhighlight(win, "NormalNC", "NormalNC")
	replace_winhighlight(win, "WinBar", "WinBar")
	replace_winhighlight(win, "WinBarNC", "WinBarNC")
	-- options.lua updates the active editor to the current mode scene. Diff
	-- siblings may never receive that active-window event, so ensure they still
	-- target the custom mode-aware groups used by git.lua's adaptive style.
	ensure_default_cursorline_targets(win)
	vim.b[buf].dotfiles_disable_hlchunk = true

	if opts.minimap_disabled ~= nil then
		vim.w[win].dotfiles_disable_minimap = opts.minimap_disabled
	end
	if vim.w[win][child_flag] == true and role == "revision" then
		vim.bo[buf].modifiable = false
		vim.bo[buf].readonly = true
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

local function add_buffer_map(session, buf, lhs, callback, desc, replace)
	local key = buf .. "\0" .. lhs
	local existing = vim.iter(vim.api.nvim_buf_get_keymap(buf, "n")):find(function(mapping)
		return vim.keycode(mapping.lhs) == vim.keycode(lhs)
	end)
	local owned = session.map_index and session.map_index[key]
	if owned then
		if existing and existing.desc == desc then
			return
		end
		vim.keymap.set("n", lhs, callback, { buffer = buf, desc = desc, nowait = true })
		return
	end
	if existing and existing.desc == desc then
		return
	end
	if existing and not replace then
		return
	end
	vim.keymap.set("n", lhs, callback, { buffer = buf, desc = desc, nowait = true })
	local mapping = { buf = buf, lhs = lhs, desc = desc, replaced = existing }
	session.maps[#session.maps + 1] = mapping
	session.map_index = session.map_index or {}
	session.map_index[key] = mapping
end

local function restore_buffer_map(buf, mapping)
	local replaced = mapping.replaced
	if not replaced then
		return
	end
	local opts = {
		buffer = buf,
		desc = replaced.desc,
		expr = replaced.expr == 1,
		remap = replaced.noremap == 0,
		nowait = replaced.nowait == 1,
		script = replaced.script == 1,
		silent = replaced.silent == 1,
		unique = replaced.unique == 1,
		replace_keycodes = replaced.replace_keycodes == 1,
	}
	vim.keymap.set("n", mapping.lhs, replaced.callback or replaced.rhs, opts)
end

local function remove_buffer_maps(session)
	for _, mapping in ipairs(session.maps) do
		if vim.api.nvim_buf_is_valid(mapping.buf) then
			local current = vim.iter(vim.api.nvim_buf_get_keymap(mapping.buf, "n")):find(function(candidate)
				return vim.keycode(candidate.lhs) == vim.keycode(mapping.lhs)
			end)
			if current and current.desc == mapping.desc then
				pcall(vim.keymap.del, "n", mapping.lhs, { buffer = mapping.buf })
				restore_buffer_map(mapping.buf, mapping)
			end
		end
	end
	session.map_index = {}
	return {}
end

local function cleanup_session(tab, session, focus_underlay)
	if session.cleanup_scheduled then
		return
	end
	session.cleanup_scheduled = true
	local navigate_command = session.navigate_command
	session.navigate_command = nil
	stop_background_minimap_monitor(session)
	stop_snapshot_resize_monitor(session)
	release_global_statusline(session.statusline_guard)
	if sessions[tab] == session then
		sessions[tab] = nil
	end
	session.maps = remove_buffer_maps(session)
	vim.schedule(function()
		local restored_source = restore_underlay(session)
		restore_background_minimaps(session)
		if
			focus_underlay
			and vim.api.nvim_win_is_valid(session.underlay.win)
			and vim.api.nvim_win_get_tabpage(session.underlay.win) == vim.api.nvim_get_current_tabpage()
		then
			vim.api.nvim_set_current_win(session.underlay.win)
		end
		refresh_minimap()
		discard_minimap_margin_transfer(session.underlay.win)
		if
			navigate_command
			and vim.api.nvim_get_current_tabpage() == tab
			and vim.api.nvim_win_is_valid(session.underlay.win)
			and sessions[tab] == nil
			and pending_sessions[tab] == nil
		then
			vim.api.nvim_set_current_win(session.underlay.win)
			-- A recovery navigation opens its replacement session before this
			-- cleanup's final scheduled appearance restore. Restore now so the new
			-- session snapshots the real editor instead of the suppressed underlay.
			restore_underlay_appearance(session.underlay, restored_source)
			vim.cmd.redrawtabline()
			local navigated, navigate_error = pcall(vim.cmd, navigate_command)
			if not navigated then
				vim.notify(("Unable to navigate Git diff peek buffer: %s"):format(navigate_error), vim.log.levels.ERROR)
			end
			local target_win = session.underlay.win
			local target_buf = vim.api.nvim_win_is_valid(target_win) and vim.api.nvim_win_get_buf(target_win) or nil
			-- BufferLineCycle can trigger BufEnter providers that establish the
			-- target's window appearance. Snapshot on the next tick after they run.
			vim.schedule(function()
				if
					sessions[tab] == nil
					and pending_sessions[tab] == nil
					and vim.api.nvim_get_current_tabpage() == tab
					and vim.api.nvim_win_is_valid(target_win)
					and vim.api.nvim_win_get_tabpage(target_win) == tab
					and vim.api.nvim_win_get_buf(target_win) == target_buf
					and vim.api.nvim_get_current_win() == target_win
				then
					M.toggle()
				end
			end)
		end
		-- Buffer restoration and the final focus both fire providers which schedule
		-- window-local updates. Restore the exact pre-popup sentinel after them, but
		-- never let an old close callback overwrite a newer session in the same tab.
		vim.schedule(function()
			local active = sessions[tab]
			local pending = pending_sessions[tab]
			if (active and active ~= session) or (pending and pending ~= session) then
				return
			end
			restore_underlay_appearance(session.underlay, restored_source)
		end)
	end)
end

local function cycle_popup_buffer(session, command)
	if pane_index(session, vim.api.nvim_get_current_win()) == nil or not session.layout:valid() then
		return
	end
	if session.navigate_command then
		return
	end
	session.navigate_command = command
	session.layout:close()
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
			add_buffer_map(session, buf, "[[", function()
				cycle_popup_buffer(session, "BufferLineCyclePrev")
			end, "Previous Git diff peek buffer", true)
			add_buffer_map(session, buf, "]]", function()
				cycle_popup_buffer(session, "BufferLineCycleNext")
			end, "Next Git diff peek buffer", true)
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
		release_global_statusline(source.statusline_guard)
		return
	end

	local diff_wins = sorted_diff_windows(tab, source_win, source_buf)
	if #diff_wins < 2 then
		close_regular_diff(tab)
		release_global_statusline(source.statusline_guard)
		vim.notify("No Git revision available for this buffer", vim.log.levels.INFO)
		return
	end

	local snacks = require("snacks")
	local source_chrome = source.chrome
	local session = {
		maps = {},
		panes = {},
		snapshot = source.snapshot,
		statusline_guard = source.statusline_guard,
		underlay = source,
	}
	local wins = {}
	local children = { box = "horizontal" }
	local source_pane
	local revision_wins = {}
	local function revision_pane_width()
		local root = session.layout and session.layout.root
		if not root or not root.win or not vim.api.nvim_win_is_valid(root.win) then
			return 0
		end
		local equal_width = math.floor(vim.api.nvim_win_get_width(root.win) / 2)
		return math.max(1, equal_width - math.floor(active_minimap_width(tab) / 2))
	end
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
			-- apply_editor_chrome() establishes the popup child/role metadata used by
			-- minimap's is_code_window() predicate. Inherit before the first refresh.
			inherit_minimap_margin(win, source_win)
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
			width = role == "revision" and revision_pane_width or nil,
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
			backdrop = cover_backdrop(),
			width = 0.95,
			height = 0.95,
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
		prepare_minimap_margin_transfer(source_win)
		vim.wo[source_win].diff = false
		session.underlay.scratch = create_underlay_scratch()
		vim.w[source_win].dotfiles_git_diff_peek_underlay = true
		set_window_buffer_keepalt(source_win, session.underlay.scratch)
		layout:show()
		if not layout.root.backdrop or not layout.root.backdrop:valid() then
			error("Git diff peek full-editor cover was not created")
		end
		render_frozen_screen(session)
		suppress_underlay(session.underlay)

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
			suppress_underlay(session.underlay)
			refresh_minimap()
		end)
		install_buffer_maps(session)
		start_background_minimap_monitor(session, tab)
		start_snapshot_resize_monitor(session, tab)
		-- FileType/BufEnter handlers may schedule ordinary buffer-cycle mappings
		-- while the floating panes are created. Reassert popup-local navigation once
		-- after those handlers without adding a redraw-time or repeating watcher.
		vim.schedule(function()
			if sessions[tab] == session and session.layout and session.layout:valid() then
				install_buffer_maps(session)
			end
		end)
		if expand_all_folds then
			open_all_folds(session)
		end
	end, debug.traceback)

	if not ok then
		-- Close the temporary diff windows before layout cleanup queues its final
		-- underlay restore. WinClosed providers may schedule window-local chrome;
		-- cleanup must run after those callbacks have been enqueued.
		close_regular_diff(tab)
		if session.layout then
			pcall(function()
				session.layout:close()
			end)
		end
		cleanup_session(tab, session, true)
		vim.notify(tostring(layout_error), vim.log.levels.ERROR)
	end
end

local function open_empty_revision_diff(source_win, source_buf, revision)
	local revision_buf = vim.api.nvim_create_buf(false, true)
	local revision_name = ("gitsigns://%s//%s:%s"):format(revision.git_dir, revision.base, revision.relpath)
	vim.api.nvim_buf_set_name(revision_buf, revision_name)
	vim.bo[revision_buf].bufhidden = "wipe"
	vim.bo[revision_buf].buftype = "nowrite"
	vim.bo[revision_buf].swapfile = false
	M.prepare_revision_buffer(revision_buf, source_buf)
	vim.bo[revision_buf].modifiable = false
	vim.bo[revision_buf].readonly = true

	vim.api.nvim_set_current_win(source_win)
	vim.cmd("belowright vsplit")
	local revision_win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(revision_win, revision_buf)
	vim.wo[revision_win].diff = true
	vim.wo[source_win].diff = true
	vim.api.nvim_set_current_win(source_win)
end

function M.toggle()
	local tab = vim.api.nvim_get_current_tabpage()
	local session = session_for_tab(tab)
	if session then
		-- Snacks may defer on_close until its windows finish closing. Release the
		-- global statusline ownership synchronously so a rapid close/reopen cycle
		-- snapshots the real pre-popup policy instead of inheriting laststatus=3.
		release_global_statusline(session.statusline_guard)
		session.layout:close()
		return
	end
	local pending = pending_sessions[tab]
	if pending then
		pending.cancelled = true
		pending.maps = remove_buffer_maps(pending)
		pending_sessions[tab] = nil
		release_global_statusline(pending.statusline_guard)
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
	local diff_base, base_error = require("config.git_diff_context").resolve_base(source_buf)
	if not diff_base then
		vim.notify(("Unable to resolve Git diff base: %s"):format(base_error or "unknown error"), vim.log.levels.ERROR)
		return
	end
	local source = {
		win = source_win,
		buf = source_buf,
		view = vim.fn.winsaveview(),
		chrome = snapshot_editor_chrome(source_win),
		appearance = snapshot_underlay_appearance(source_win),
		disable_minimap = vim.w[source_win].dotfiles_disable_minimap,
		disable_hlchunk = vim.b[source_buf].dotfiles_disable_hlchunk,
		underlay_flag = vim.w[source_win].dotfiles_git_diff_peek_underlay,
	}
	source.statusline_guard = acquire_global_statusline()
	local captured, snapshot = pcall(capture_frozen_screen)
	if not captured then
		release_global_statusline(source.statusline_guard)
		vim.notify(("Unable to capture Git diff peek background: %s"):format(snapshot), vim.log.levels.ERROR)
		return
	end
	source.snapshot = snapshot
	pending = {
		cancelled = false,
		expand_all_folds = false,
		maps = {},
		statusline_guard = source.statusline_guard,
		tab = tab,
	}
	pending_sessions[tab] = pending
	add_buffer_map(pending, source_buf, "zR", function()
		pending.expand_all_folds = true
		vim.cmd.normal({ args = { "zR" }, bang = true })
	end, "Open pending Git diff folds")
	local function finish_open(err)
		pending.maps = remove_buffer_maps(pending)
		if pending_sessions[tab] ~= pending or pending.cancelled then
			close_regular_diff(tab)
			release_global_statusline(source.statusline_guard)
			return
		end
		pending_sessions[tab] = nil
		if err then
			close_regular_diff(tab)
			release_global_statusline(source.statusline_guard)
			vim.notify(tostring(err), vim.log.levels.ERROR)
			return
		end
		local opened, open_error = xpcall(function()
			open_layout(tab, source, pending.expand_all_folds)
		end, debug.traceback)
		if not opened then
			close_regular_diff(tab)
			release_global_statusline(source.statusline_guard)
			vim.notify(tostring(open_error), vim.log.levels.ERROR)
		end
	end
	local added_revision = require("config.git_diff_context").added_file_revision(source_buf, diff_base)
	local ok, diff_error
	if added_revision then
		ok, diff_error = pcall(function()
			open_empty_revision_diff(source_win, source_buf, added_revision)
			finish_open()
		end)
	else
		ok, diff_error = pcall(require("gitsigns").diffthis, diff_base, { vertical = true }, finish_open)
	end
	if not ok then
		pending.maps = remove_buffer_maps(pending)
		if pending_sessions[tab] == pending then
			pending_sessions[tab] = nil
		end
		close_regular_diff(tab)
		release_global_statusline(source.statusline_guard)
		vim.notify(tostring(diff_error), vim.log.levels.ERROR)
	end
end

return M
