local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
vim.opt.runtimepath:prepend(nvim_root)
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")
package.loaded["config.git_diff_peek"] = nil
if vim.loader and vim.loader.reset then
	vim.loader.reset()
end
local loaded_module = assert(package.searchpath("config.git_diff_peek", package.path))
local expected_module = vim.fs.joinpath(nvim_root, "lua/config/git_diff_peek.lua")
assert(
	vim.uv.fs_realpath(loaded_module) == vim.uv.fs_realpath(expected_module),
	("git_diff_peek loaded from %s, expected %s"):format(loaded_module, expected_module)
)
local mini_map = require("mini.map")
assert(package.loaded["mini.map"] == mini_map, "mini.map must be loaded for popup minimap QA")
assert(
	vim.o.columns >= 190 and vim.o.lines >= 65,
	("Git diff peek QA requires a 190x65 or larger UI, got %dx%d"):format(vim.o.columns, vim.o.lines)
)

local source_win = vim.api.nvim_get_current_win()
local source_buf = vim.api.nvim_get_current_buf()
local original_underlay_flag = vim.w[source_win].dotfiles_git_diff_peek_underlay
local original_disable_minimap = vim.w[source_win].dotfiles_disable_minimap
local original_hlchunk = vim.b[source_buf].dotfiles_disable_hlchunk

local function alternate_buffer(win)
	return vim.api.nvim_win_call(win, function()
		return vim.fn.bufnr("#")
	end)
end

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

local function underlay_appearance(win)
	local options = {}
	for _, name in ipairs(underlay_option_names) do
		options[name] = vim.api.nvim_get_option_value(name, { scope = "local", win = win })
	end
	return {
		hl_ns = vim.api.nvim_get_hl_ns({ winid = win }),
		options = options,
	}
end

vim.api.nvim_buf_set_name(source_buf, "/tmp/dotfiles-git-diff-peek.lua")
vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, {
	"local value = 1",
	"",
	"return value",
})
vim.bo[source_buf].filetype = "bigfile"
vim.bo[source_buf].syntax = "lua"
vim.api.nvim_win_set_cursor(source_win, { 3, 0 })
local alternate_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(alternate_buf, 0, -1, false, { "alternate buffer sentinel" })
vim.api.nvim_win_set_buf(source_win, alternate_buf)
vim.api.nvim_win_set_buf(source_win, source_buf)
assert(alternate_buffer(source_win) == alternate_buf, "the fixture must install a known alternate buffer")
local navigation_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(navigation_buf, "/tmp/dotfiles-git-diff-peek-navigation.lua")
vim.api.nvim_buf_set_lines(navigation_buf, 0, -1, false, { "local navigation_target = true" })
vim.bo[navigation_buf].filetype = "lua"
vim.api.nvim_win_set_buf(source_win, navigation_buf)
vim.api.nvim_win_set_buf(source_win, alternate_buf)
vim.api.nvim_win_set_buf(source_win, source_buf)

local defer_diff_callback = false
local pending_diff_callback
local mutate_source_statuscolumn = false
local mutate_popup_revision_statuscolumn = false
local diffthis_bases = {}
package.loaded.gitsigns = {
	diffthis = function(base, _, callback)
		diffthis_bases[#diffthis_bases + 1] = base
		local diff_source_buf = vim.api.nvim_win_get_buf(source_win)
		local revision_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(revision_buf, "gitsigns:///tmp/.git//:0:dotfiles-git-diff-peek.lua")
		local revision_lines = vim.api.nvim_buf_get_lines(diff_source_buf, 0, -1, false)
		revision_lines[1] = "local value = 0"
		vim.api.nvim_buf_set_lines(revision_buf, 0, -1, false, revision_lines)
		vim.bo[revision_buf].bufhidden = "wipe"
		vim.bo[revision_buf].buftype = "acwrite"
		vim.bo[revision_buf].filetype = "bigfile"
		vim.bo[revision_buf].syntax = "lua"
		vim.cmd("belowright vsplit")
		local revision_win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(revision_win, revision_buf)
		vim.wo[revision_win].diff = true
		vim.wo[source_win].diff = true
		vim.api.nvim_set_current_win(source_win)
		local source_statuscolumn = vim.wo[source_win].statuscolumn
		if mutate_source_statuscolumn then
			vim.wo[source_win].statuscolumn = ""
		end
		if defer_diff_callback then
			pending_diff_callback = callback
		else
			callback()
		end
		if mutate_source_statuscolumn and vim.api.nvim_win_is_valid(source_win) then
			vim.wo[source_win].statuscolumn = source_statuscolumn
		end
		if mutate_popup_revision_statuscolumn then
			for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
				if vim.w[win].dotfiles_git_diff_peek_role == "revision" then
					vim.wo[win].statuscolumn = ""
				end
			end
		end
	end,
}

local peek = require("config.git_diff_peek")
package.loaded["config.git_diff_peek"] = peek
assert(type(peek.apply_editor_chrome) == "function", "source git_diff_peek must expose apply_editor_chrome")
local module_source = assert(debug.getinfo(peek.apply_editor_chrome, "S").source):gsub("^@", "")
assert(
	vim.uv.fs_realpath(module_source) == vim.uv.fs_realpath(expected_module),
	("config.git_diff_peek loaded from %s, expected %s"):format(module_source, expected_module)
)
dofile(vim.fs.joinpath(nvim_root, "lua/plugins/git.lua"))

local bigfile_buf = vim.api.nvim_create_buf(false, true)
vim.bo[bigfile_buf].filetype = "bigfile"
local bigfile_win = vim.api.nvim_open_win(bigfile_buf, false, {
	relative = "editor",
	row = 1,
	col = 1,
	width = 20,
	height = 2,
	style = "minimal",
})
local explicit_statuscolumn = "%=%l"
peek.apply_editor_chrome(bigfile_win, { role = "worktree", statuscolumn = explicit_statuscolumn })
assert(vim.wo[bigfile_win].statuscolumn == "", "bigfile worktree chrome must suppress statuscolumn")
assert(vim.wo[bigfile_win].foldcolumn == "1", "bigfile chrome must retain the fold rail")
assert(vim.wo[bigfile_win].signcolumn == "no", "bigfile chrome must retain the sign rail contract")
assert(vim.wo[bigfile_win].numberwidth == 3, "bigfile chrome must retain the number width")
vim.w[bigfile_win].dotfiles_git_diff_peek_role = "revision"
peek.apply_editor_chrome(bigfile_win, { statuscolumn = explicit_statuscolumn })
assert(
	vim.wo[bigfile_win].statuscolumn == explicit_statuscolumn,
	"bigfile revision chrome must preserve statuscolumn when a later refresh omits opts.role"
)
assert(vim.wo[bigfile_win].foldcolumn == "1", "bigfile revision chrome must retain the fold rail")
assert(vim.wo[bigfile_win].signcolumn == "no", "bigfile revision chrome must retain the sign rail contract")
assert(vim.wo[bigfile_win].numberwidth == 3, "bigfile revision chrome must retain the number width")

vim.bo[bigfile_buf].filetype = "lua"
vim.w[bigfile_win].dotfiles_git_diff_peek_role = nil
local original_global_statuscolumn = vim.go.statuscolumn
local fallback_ok, fallback_error = xpcall(function()
	local canonical_statuscolumn = "%=%l"
	vim.go.statuscolumn = canonical_statuscolumn
	vim.wo[bigfile_win].statuscolumn = ""
	peek.apply_editor_chrome(bigfile_win, {})
	assert(
		vim.wo[bigfile_win].statuscolumn == canonical_statuscolumn,
		"nil statuscolumn must fall back from an empty local value to the global canonical value"
	)
	peek.apply_editor_chrome(bigfile_win, { statuscolumn = "" })
	assert(vim.wo[bigfile_win].statuscolumn == "", "an explicitly empty statuscolumn must be preserved")
end, debug.traceback)
vim.go.statuscolumn = original_global_statuscolumn
assert(fallback_ok, fallback_error)
vim.api.nvim_win_close(bigfile_win, true)
vim.api.nvim_buf_delete(bigfile_buf, { force = true })

local function visible_minimap_windows()
	local result = {}
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		local buf = vim.api.nvim_win_get_buf(win)
		local config = vim.api.nvim_win_get_config(win)
		if vim.bo[buf].filetype == "minimap" and not config.hide then
			result[#result + 1] = win
		end
	end
	return result
end

mini_map.open()
local tab = vim.api.nvim_get_current_tabpage()
mini_map.refresh({}, { layout = true, integrations = false, lines = false, scrollbar = false })
assert(
	vim.wait(1500, function()
		local native = mini_map.current.win_data[tab]
		local minimaps = visible_minimap_windows()
		if not native or not vim.api.nvim_win_is_valid(native) or #minimaps ~= 1 then
			return false
		end
		local source_position = vim.api.nvim_win_get_position(source_win)
		local source_right = source_position[2] + vim.api.nvim_win_get_width(source_win)
		local native_config = vim.api.nvim_win_get_config(native)
		local display_config = vim.api.nvim_win_get_config(minimaps[1])
		return native_config.col == source_right
			and native_config.height == vim.api.nvim_win_get_height(source_win)
			and display_config.col + display_config.width == source_right
	end, 20),
	"the fixture must expose one settled ordinary minimap before popup open"
)
local baseline_native = mini_map.current.win_data[tab]
local baseline_display = visible_minimap_windows()[1]
local baseline_native_config = vim.deepcopy(vim.api.nvim_win_get_config(baseline_native))
local baseline_display_config = vim.deepcopy(vim.api.nvim_win_get_config(baseline_display))
local baseline_source_view = vim.api.nvim_win_call(source_win, vim.fn.winsaveview)
local baseline_alternate_buf = alternate_buffer(source_win)
local baseline_statuscolumn = vim.wo[source_win].statuscolumn ~= "" and vim.wo[source_win].statuscolumn
	or vim.go.statuscolumn

local function create_background_split(name, minimap_flag)
	local win
	local buf
	vim.api.nvim_win_call(source_win, function()
		vim.cmd("belowright vnew")
		win = vim.api.nvim_get_current_win()
		buf = vim.api.nvim_get_current_buf()
		vim.api.nvim_buf_set_name(buf, name)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "local background = true" })
		vim.bo[buf].filetype = "lua"
	end)
	if minimap_flag ~= nil then
		vim.w[win].dotfiles_disable_minimap = minimap_flag
	end
	return win, buf
end

local function create_background_float(text, row, col, zindex)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { text })
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "hide"
	vim.bo[buf].swapfile = false
	local win = vim.api.nvim_open_win(buf, false, {
		relative = "editor",
		row = row,
		col = col,
		width = 28,
		height = 2,
		style = "minimal",
		focusable = false,
		noautocmd = true,
		zindex = zindex,
	})
	return win, buf, vim.deepcopy(vim.api.nvim_win_get_config(win))
end

local function screen_row(row)
	local cells = {}
	for col = 1, vim.o.columns do
		cells[col] = vim.fn.screenstring(row, col)
	end
	return table.concat(cells)
end

local function background_minimap_monitor_count()
	local ids = {}
	for _, autocmd in ipairs(vim.api.nvim_get_autocmds({})) do
		if autocmd.desc == "Git diff peek background minimap ownership" then
			ids[autocmd.id] = true
		end
	end
	return vim.tbl_count(ids)
end

local function snapshot_resize_monitor_count()
	local ids = {}
	for _, autocmd in ipairs(vim.api.nvim_get_autocmds({})) do
		if autocmd.desc == "Git diff peek frozen background resize" then
			ids[autocmd.id] = true
		end
	end
	return vim.tbl_count(ids)
end

local baseline_monitor_count = background_minimap_monitor_count()
local baseline_snapshot_monitor_count = snapshot_resize_monitor_count()
local background_win, background_buf = create_background_split("/tmp/dotfiles-git-diff-peek-background.lua", false)
local disabled_background_win, disabled_background_buf =
	create_background_split("/tmp/dotfiles-git-diff-peek-disabled-background.lua", true)
local expected_cover_top = (vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1))
		and 1
	or 0
local background_float_a, background_float_buf_a, background_float_config_a =
	create_background_float("FLOAT-A-CONTENT", expected_cover_top, 0, 35)
local background_float_b, background_float_buf_b, background_float_config_b = create_background_float(
	"FLOAT-B-CONTENT",
	math.max(expected_cover_top, vim.o.lines - 4),
	math.max(0, vim.o.columns - 30),
	45
)
vim.api.nvim_set_current_win(source_win)
mini_map.refresh({}, { layout = true, integrations = false, lines = false, scrollbar = false })
assert(
	vim.wait(1500, function()
		return #visible_minimap_windows() == 2
	end, 20),
	"the multi-editor fixture must expose a second visible minimap before popup open"
)
vim.cmd.redraw({ bang = true })
local baseline_bufferline_screen = screen_row(1)
assert(baseline_bufferline_screen:find("dotfiles-git-diff-peek", 1, true))
assert(
	screen_row(expected_cover_top + 1):find("FLOAT-A-CONTENT", 1, true),
	"the background float fixture must be visible before popup open"
)

local sentinel_hl_ns = vim.api.nvim_create_namespace("dotfiles-git-diff-peek-underlay-sentinel")
vim.api.nvim_set_hl(sentinel_hl_ns, "Normal", { fg = "#ffffff", bg = "#010203" })
vim.api.nvim_win_set_hl_ns(source_win, sentinel_hl_ns)
vim.wo[source_win].cursorline = false
vim.wo[source_win].cursorcolumn = true
vim.wo[source_win].foldcolumn = "0"
local baseline_underlay_appearance = underlay_appearance(source_win)
local baseline_sidescrolloff = vim.wo[source_win].sidescrolloff
local baseline_showtabline = vim.o.showtabline
local baseline_laststatus = vim.o.laststatus

local original_hidden = vim.o.hidden
assert(vim.bo[source_buf].modified, "the hidden=false fixture requires an unsaved source buffer")
vim.o.hidden = false
mutate_source_statuscolumn = true
mutate_popup_revision_statuscolumn = true
local opened, open_error = pcall(peek.toggle)
mutate_source_statuscolumn = false
mutate_popup_revision_statuscolumn = false
vim.o.hidden = original_hidden
assert(opened, open_error)

local source_float
local revision_float
local root_float
local cover_float
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
	local config = vim.api.nvim_win_get_config(win)
	local buf = vim.api.nvim_win_get_buf(win)
	if config.relative ~= "" and vim.wo[win].diff then
		if buf == source_buf then
			source_float = win
		elseif vim.startswith(vim.api.nvim_buf_get_name(buf), "gitsigns://") then
			revision_float = win
		end
	elseif config.relative == "editor" and vim.bo[buf].filetype == "snacks_layout_box" then
		root_float = win
	elseif vim.w[win].dotfiles_git_diff_peek_cover == true then
		cover_float = win
	end
end

assert(source_float, "the worktree diff pane must be a floating window")
assert(revision_float, "the revision diff pane must be a floating window")
assert(root_float, "the diff panes must have a shared floating layout root")
assert(cover_float, "the popup must create one full-editor background cover")
local cover_buf = vim.api.nvim_win_get_buf(cover_float)
local cover_config = vim.api.nvim_win_get_config(cover_float)
assert(cover_config.relative == "editor" and cover_config.row == expected_cover_top and cover_config.col == 0)
assert(cover_config.width == vim.o.columns and cover_config.height == vim.o.lines - expected_cover_top - 1)
assert(cover_config.zindex == vim.api.nvim_win_get_config(root_float).zindex - 1)
assert(
	cover_config.zindex > background_float_config_a.zindex and cover_config.zindex > background_float_config_b.zindex
)
assert(cover_config.zindex < vim.api.nvim_win_get_config(source_float).zindex)
assert(cover_config.zindex < vim.api.nvim_win_get_config(revision_float).zindex)
assert(vim.fn.buflisted(cover_buf) == 0 and vim.bo[cover_buf].buftype == "nofile")
assert(vim.bo[cover_buf].bufhidden == "wipe" and not vim.bo[cover_buf].swapfile)
assert(not vim.bo[cover_buf].modifiable and vim.bo[cover_buf].undolevels == -1)
assert(vim.wo[cover_float].winblend == 0 and vim.wo[cover_float].fillchars:find("eob: ", 1, true))
local cover_normal = assert(vim.wo[cover_float].winhighlight:match("Normal:([^,]+)"))
assert(cover_normal == "DotfilesGitDiffPeekFrozen")
assert(vim.api.nvim_get_hl(0, { name = cover_normal, link = false }).fg ~= nil)
assert(
	vim.api.nvim_buf_get_lines(cover_buf, 0, 1, false)[1]:find("FLOAT-A-CONTENT", 1, true),
	"the frozen background did not capture the pre-popup screen"
)
vim.api.nvim_win_set_config(cover_float, {
	width = vim.o.columns - 3,
	height = vim.o.lines - expected_cover_top - 3,
})
vim.api.nvim_exec_autocmds("VimResized", { modeline = false })
assert(
	vim.wait(1000, function()
		local resized = vim.api.nvim_win_get_config(cover_float)
		return resized.row == expected_cover_top
			and resized.width == vim.o.columns
			and resized.height == vim.o.lines - expected_cover_top - 1
			and vim.api.nvim_buf_line_count(cover_buf) == resized.height
	end, 20),
	"the full-editor cover did not re-evaluate its resize functions"
)
vim.cmd.redraw({ bang = true })
assert(screen_row(1):find("dotfiles-git-diff-peek", 1, true), "the full-editor cover obscured the existing bufferline")
assert(
	screen_row(expected_cover_top + 1):find("FLOAT", 1, true),
	"the popup margin does not show the frozen background"
)
assert(
	vim.api.nvim_win_get_position(revision_float)[2] < vim.api.nvim_win_get_position(source_float)[2],
	"the revision pane must be left of the worktree pane"
)
assert(
	vim.wait(1000, function()
		return vim.wo[revision_float].statuscolumn == baseline_statuscolumn
			and vim.bo[vim.api.nvim_win_get_buf(revision_float)].filetype == "lua"
			and vim.treesitter.highlighter.active[vim.api.nvim_win_get_buf(revision_float)] ~= nil
	end, 20),
	("scheduled popup chrome mismatch: status=%q expected=%q ft=%q syntax=%q treesitter=%s"):format(
		vim.wo[revision_float].statuscolumn,
		baseline_statuscolumn,
		vim.bo[vim.api.nvim_win_get_buf(revision_float)].filetype,
		vim.bo[vim.api.nvim_win_get_buf(revision_float)].syntax,
		tostring(vim.treesitter.highlighter.active[vim.api.nvim_win_get_buf(revision_float)] ~= nil)
	)
)
assert(not vim.wo[source_win].diff, "the underlying editor window must leave diff mode")
local underlay_scratch = vim.api.nvim_win_get_buf(source_win)
assert(underlay_scratch ~= source_buf, "the underlay must detach the source buffer while the popup is visible")
assert(vim.fn.buflisted(underlay_scratch) == 0, "the underlay scratch must be unlisted")
assert(vim.bo[underlay_scratch].buftype == "nofile", "the underlay scratch must be a nofile buffer")
assert(vim.bo[underlay_scratch].bufhidden == "wipe", "the underlay scratch must wipe when hidden")
assert(not vim.bo[underlay_scratch].swapfile, "the underlay scratch must not create swap files")
assert(not vim.bo[underlay_scratch].modifiable, "the underlay scratch must not accept edits")
assert(vim.bo[underlay_scratch].undolevels == -1, "the underlay scratch must not retain undo history")
local underlay_namespace = assert(vim.api.nvim_get_namespaces()["dotfiles-git-diff-peek-underlay"])
assert(vim.api.nvim_get_hl_ns({ winid = source_win }) == underlay_namespace, "underlay namespace mismatch")
assert(not vim.wo[source_win].number and not vim.wo[source_win].relativenumber)
assert(vim.wo[source_win].statuscolumn == "" and vim.wo[source_win].foldcolumn == "0")
assert(vim.wo[source_win].signcolumn == "no")
assert(not vim.wo[source_win].cursorline and not vim.wo[source_win].cursorcolumn)
assert(not vim.wo[source_win].list and vim.wo[source_win].colorcolumn == "")
assert(vim.wo[source_win].winbar == " " and vim.wo[source_win].statusline == " ")
assert(vim.wo[source_win].fillchars:find("eob: ", 1, true), "underlay must render blank end-of-buffer cells")
for _, group in ipairs({ "Normal", "NormalNC", "EndOfBuffer", "StatusLine", "WinBar", "WinSeparator" }) do
	local attributes = vim.api.nvim_get_hl(underlay_namespace, { name = group, link = false })
	assert(attributes.fg == nil and attributes.bg == nil, group .. " must remain transparent in the underlay")
end
assert(vim.o.showtabline == baseline_showtabline, "underlay suppression changed the global bufferline")
assert(vim.o.laststatus == 3, "Git diff peek must expose Heirline as a global statusline")
assert(snapshot_resize_monitor_count() == baseline_snapshot_monitor_count + 1)
local source_windows = vim.fn.win_findbuf(source_buf)
assert(
	#source_windows == 1 and source_windows[1] == source_float,
	"the worktree float must be the only window displaying the source buffer"
)
assert(alternate_buffer(source_win) == baseline_alternate_buf, "scratch detachment changed the alternate buffer")
assert(
	vim.api.nvim_win_get_config(source_float).relative == "win"
		and vim.api.nvim_win_get_config(revision_float).relative == "win",
	"both diff panes must be placed inside the shared popup"
)
assert(vim.api.nvim_get_current_win() == source_float, "the popup must focus the editable worktree pane")
assert(vim.api.nvim_win_get_cursor(source_float)[1] == 3, "the worktree pane must preserve the source cursor")
assert(vim.bo[source_buf].modifiable and not vim.bo[source_buf].readonly and vim.bo[source_buf].buftype == "")
local revision_buf = vim.api.nvim_win_get_buf(revision_float)
assert(not vim.bo[revision_buf].modifiable and vim.bo[revision_buf].readonly)
local revision_edit_ok = pcall(vim.api.nvim_buf_set_lines, revision_buf, 0, 0, false, { "forbidden revision edit" })
assert(not revision_edit_ok, "popup revision buffer accepted an edit")

local function popup_child_for(buf)
	return vim.iter(vim.api.nvim_tabpage_list_wins(0)):find(function(win)
		return vim.w[win].dotfiles_git_diff_peek_child == true and vim.api.nvim_win_get_buf(win) == buf
	end)
end

local function buffer_map(buf, lhs, desc)
	return vim.iter(vim.api.nvim_buf_get_keymap(buf, "n")):find(function(mapping)
		return vim.keycode(mapping.lhs) == vim.keycode(lhs) and mapping.desc == desc
	end)
end

local function popup_map(win, lhs, desc)
	return buffer_map(vim.api.nvim_win_get_buf(win), lhs, desc)
end

local function wait_for_popup_buffer(buf)
	return vim.wait(1000, function()
		local child = popup_child_for(buf)
		return child ~= nil and vim.api.nvim_get_current_win() == child
	end, 20)
end

pcall(vim.api.nvim_del_user_command, "BufferLineCycleNext")
pcall(vim.api.nvim_del_user_command, "BufferLineCyclePrev")
local navigation_commands = {}
local fail_navigation_command = false
local latest_navigation_appearance
local navigation_focus_redirect
local function cycle_navigation(direction)
	navigation_commands[#navigation_commands + 1] = direction
	if fail_navigation_command then
		error("intentional bufferline failure")
	end
	vim.api.nvim_win_set_buf(source_win, vim.api.nvim_get_current_buf() == source_buf and navigation_buf or source_buf)
	vim.schedule(function()
		latest_navigation_appearance = underlay_appearance(source_win)
	end)
	if navigation_focus_redirect then
		vim.schedule(function()
			if vim.api.nvim_win_is_valid(navigation_focus_redirect) then
				vim.api.nvim_set_current_win(navigation_focus_redirect)
			end
		end)
	end
end
vim.api.nvim_create_user_command("BufferLineCycleNext", function()
	cycle_navigation("Next")
end, {})
vim.api.nvim_create_user_command("BufferLineCyclePrev", function()
	cycle_navigation("Prev")
end, {})

local old_navigation_cover = cover_float
local old_navigation_snapshot = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(old_navigation_cover), 0, -1, false)
local original_bufferline = package.loaded["config.bufferline"]
package.loaded["config.bufferline"] = {
	cycle = function()
		error("popup navigation must invoke the native BufferLineCycle command")
	end,
}
local next_buffer = assert(popup_map(source_float, "]]", "Next Git diff peek buffer"))
next_buffer.callback()
next_buffer.callback()
assert(wait_for_popup_buffer(navigation_buf), "next popup buffer did not open in bufferline order")
local navigation_cover = assert(vim.iter(vim.api.nvim_tabpage_list_wins(0)):find(function(win)
	return vim.w[win].dotfiles_git_diff_peek_cover == true
end))
assert(
	navigation_cover ~= old_navigation_cover and not vim.api.nvim_win_is_valid(old_navigation_cover),
	"next popup buffer did not replace the frozen background"
)
assert(
	vim.wait(1000, function()
		return vim.deep_equal(
			vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(navigation_cover), 0, -1, false),
			old_navigation_snapshot
		)
	end, 20),
	"next popup buffer did not reuse the frozen background"
)
assert(screen_row(1):find("navigation", 1, true), "next popup buffer did not refresh the bufferline")
assert(
	vim.wait(1000, function()
		return buffer_map(source_buf, "[[", "Previous buffer") ~= nil
			and buffer_map(source_buf, "]]", "Next buffer") ~= nil
	end, 20),
	"popup navigation did not restore the ordinary previous/next-buffer mappings"
)
assert(
	not buffer_map(source_buf, "[[", "Previous Git diff peek buffer"),
	"popup previous mapping leaked into the closed buffer"
)
assert(
	not buffer_map(source_buf, "]]", "Next Git diff peek buffer"),
	"popup next mapping leaked into the closed buffer"
)

local navigation_float = assert(popup_child_for(navigation_buf))
assert(popup_map(navigation_float, "]]", "Next Git diff peek buffer")).callback()
assert(wait_for_popup_buffer(source_buf), "next popup buffer did not wrap at the bufferline boundary")
source_float = assert(popup_child_for(source_buf))
assert(popup_map(source_float, "[[", "Previous Git diff peek buffer")).callback()
assert(wait_for_popup_buffer(navigation_buf), "previous popup buffer did not wrap at the bufferline boundary")
navigation_float = assert(popup_child_for(navigation_buf))
assert(popup_map(navigation_float, "[[", "Previous Git diff peek buffer")).callback()
assert(wait_for_popup_buffer(source_buf), "previous popup buffer did not return to the prior buffer")
assert(
	vim.deep_equal(navigation_commands, { "Next", "Next", "Prev", "Prev" }),
	("popup navigation direction/count mismatch: %s"):format(vim.inspect(navigation_commands))
)
assert(latest_navigation_appearance, "bufferline navigation did not settle the source appearance")
baseline_underlay_appearance = latest_navigation_appearance
source_float = assert(popup_child_for(source_buf))
revision_float = vim.iter(vim.api.nvim_tabpage_list_wins(0)):find(function(win)
	return vim.w[win].dotfiles_git_diff_peek_child == true and vim.w[win].dotfiles_git_diff_peek_role == "revision"
end)
cover_float = vim.iter(vim.api.nvim_tabpage_list_wins(0)):find(function(win)
	return vim.w[win].dotfiles_git_diff_peek_cover == true
end)
assert(revision_float and cover_float, "buffer navigation did not preserve the popup layout")

local failed_navigation_old_source = source_float
fail_navigation_command = true
assert(popup_map(source_float, "]]", "Next Git diff peek buffer")).callback()
assert(
	vim.wait(1000, function()
		local child = popup_child_for(source_buf)
		return not vim.api.nvim_win_is_valid(failed_navigation_old_source)
			and child ~= nil
			and child ~= failed_navigation_old_source
			and vim.api.nvim_get_current_win() == child
	end, 20),
	"a failed bufferline command did not create a new original-file popup"
)
assert(
	vim.deep_equal(navigation_commands, { "Next", "Next", "Prev", "Prev", "Next" }),
	("failed navigation command was not recorded exactly once: %s"):format(vim.inspect(navigation_commands))
)
package.loaded["config.bufferline"] = original_bufferline
fail_navigation_command = false
source_float = assert(popup_child_for(source_buf))
revision_float = vim.iter(vim.api.nvim_tabpage_list_wins(0)):find(function(win)
	return vim.w[win].dotfiles_git_diff_peek_child == true and vim.w[win].dotfiles_git_diff_peek_role == "revision"
end)
cover_float = vim.iter(vim.api.nvim_tabpage_list_wins(0)):find(function(win)
	return vim.w[win].dotfiles_git_diff_peek_cover == true
end)
root_float = vim.iter(vim.api.nvim_tabpage_list_wins(0)):find(function(win)
	local config = vim.api.nvim_win_get_config(win)
	return config.relative == "editor" and vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "snacks_layout_box"
end)
assert(revision_float and cover_float and root_float, "failed navigation command did not preserve the popup layout")
cover_buf = vim.api.nvim_win_get_buf(cover_float)
cover_config = vim.api.nvim_win_get_config(cover_float)
underlay_scratch = vim.api.nvim_win_get_buf(source_win)
-- Bufferline navigation intentionally changes the alternate buffer; closing the
-- recovered popup must preserve that latest ordinary-editor state.
baseline_alternate_buf = alternate_buffer(source_win)

local function option_snapshot(win)
	return {
		foldcolumn = vim.wo[win].foldcolumn,
		foldenable = vim.wo[win].foldenable,
		foldlevel = vim.wo[win].foldlevel,
		foldmethod = vim.wo[win].foldmethod,
		wrap = vim.wo[win].wrap,
		signcolumn = vim.wo[win].signcolumn,
		statuscolumn = vim.wo[win].statuscolumn,
		number = vim.wo[win].number,
		relativenumber = vim.wo[win].relativenumber,
		numberwidth = vim.wo[win].numberwidth,
		winbar = vim.wo[win].winbar,
		winhighlight = vim.wo[win].winhighlight,
		fillchars = vim.wo[win].fillchars,
		cursorline = vim.wo[win].cursorline,
		cursorlineopt = vim.wo[win].cursorlineopt,
	}
end

local function common_style_snapshot(win)
	local style = option_snapshot(win)
	style.winhighlight = nil
	style.statuscolumn = nil
	style.winbar = nil
	-- The two synchronized cursors can sit on different native diff classes;
	-- cursorlineopt is intentionally adaptive per pane rather than shared chrome.
	style.cursorlineopt = nil
	return style
end

local function dashboard_rail_snapshot(win)
	return {
		foldcolumn = vim.wo[win].foldcolumn,
		signcolumn = vim.wo[win].signcolumn,
		statuscolumn = vim.wo[win].statuscolumn,
		number = vim.wo[win].number,
		relativenumber = vim.wo[win].relativenumber,
		numberwidth = vim.wo[win].numberwidth,
	}
end

local function winhighlight_target(win, source)
	for entry in vim.wo[win].winhighlight:gmatch("[^,]+") do
		local lhs, rhs = entry:match("^([^:]+):(.+)$")
		if lhs == source then
			return rhs
		end
	end
end

local function rendered_winbar(win)
	return vim.api.nvim_eval_statusline(vim.wo[win].winbar, { winid = win }).str
end

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

assert(vim.o.foldlevelstart == 99, "popup styling must not change the global foldlevelstart")
for _, win in ipairs({ source_float, revision_float }) do
	local style = option_snapshot(win)
	assert(
		vim.w[win].dotfiles_git_diff_peek_child == true,
		("only popup children must carry the explicit child flag: win=%d value=%s"):format(
			win,
			vim.inspect(vim.w[win].dotfiles_git_diff_peek_child)
		)
	)
	assert(style.foldcolumn == "1", "popup children must use a fixed one-cell fold rail")
	assert(style.foldenable and style.foldlevel == 0 and style.foldmethod == "diff", "popup fold options mismatch")
	assert(style.wrap, "popup children must match direct Diffview wrapping")
	assert(style.signcolumn == "no", "popup children must use the custom statuscolumn without signcolumn")
	assert(style.number and style.relativenumber and style.numberwidth == 3, "popup number options mismatch")
	if vim.w[win].dotfiles_git_diff_peek_role == "revision" then
		assert(style.statuscolumn == baseline_statuscolumn, "popup revision must retain the dashboard statuscolumn")
	else
		assert(style.statuscolumn == "", "popup bigfile worktree must suppress statuscolumn")
	end
	local cursor_has_diff = vim.api.nvim_win_call(win, function()
		local line = vim.api.nvim_win_get_cursor(win)[1]
		return vim.fn.diff_hlID(line, 1) ~= 0
	end)
	assert(
		style.cursorline and style.cursorlineopt == (cursor_has_diff and "number" or "both"),
		"popup cursorline options mismatch"
	)
	assert(winhighlight_target(win, "Normal") == "Normal", "popup Normal must use the editor scene")
	assert(winhighlight_target(win, "NormalNC") == "NormalNC", "popup NormalNC must use the editor scene")
	assert(winhighlight_target(win, "WinBar") == "WinBar", "popup WinBar must use the editor scene")
	assert(winhighlight_target(win, "WinBarNC") == "WinBarNC", "popup WinBarNC must use the editor scene")
	assert(style.fillchars:find("diff: ", 1, true), "popup children must use blank diff filler")
	if vim.w[win].dotfiles_git_diff_peek_role == "revision" then
		assert(style.winbar:find("revision_winbar", 1, true), "popup revision must use its safe breadcrumb wrapper")
	else
		assert(style.winbar:find("dropbar", 1, true), "popup worktree must retain the Dropbar winbar expression")
	end
end
assert(
	vim.wo[revision_float].statuscolumn == baseline_statuscolumn,
	"popup revision must retain the pre-Gitsigns statuscolumn snapshot"
)
local direct_worktree_rail = {
	foldcolumn = "1",
	signcolumn = "no",
	statuscolumn = "",
	number = true,
	relativenumber = true,
	numberwidth = 3,
}
local direct_revision_rail = vim.tbl_extend("force", {}, direct_worktree_rail, { statuscolumn = baseline_statuscolumn })
assert(
	vim.deep_equal(dashboard_rail_snapshot(source_float), direct_worktree_rail)
		and vim.deep_equal(dashboard_rail_snapshot(revision_float), direct_revision_rail),
	"popup fold/sign/number rails must match the direct Diffview dashboard contract"
)
assert(vim.w[source_float].dotfiles_git_diff_peek_role == "worktree")
assert(vim.w[revision_float].dotfiles_git_diff_peek_role == "revision")
assert(vim.w[source_win].dotfiles_git_diff_peek_underlay == true, "the underlay must relinquish minimap ownership")
assert(vim.w[source_float].dotfiles_disable_minimap == false, "the worktree child must own the minimap")
assert(vim.w[revision_float].dotfiles_disable_minimap == true, "the revision child must not own a minimap")
assert(
	vim.w[background_win].dotfiles_disable_minimap == true,
	"the popup must temporarily exclude background editors from minimap ownership"
)
assert(vim.w[disabled_background_win].dotfiles_disable_minimap == true)
assert(
	background_minimap_monitor_count() == baseline_monitor_count + 1,
	"the popup must install exactly one session background minimap monitor"
)

local during_popup_win, during_popup_buf = create_background_split("/tmp/dotfiles-git-diff-peek-during-popup.lua", nil)
assert(
	vim.wait(1000, function()
		return vim.w[during_popup_win].dotfiles_disable_minimap == true and #visible_minimap_windows() == 1
	end, 20),
	"a background editor created during the popup retained minimap ownership"
)

local closed_background_win, closed_background_buf =
	create_background_split("/tmp/dotfiles-git-diff-peek-closed-background.lua", nil)
assert(
	vim.wait(1000, function()
		return vim.w[closed_background_win].dotfiles_disable_minimap == true
	end, 20),
	"the closed-window fixture was not captured by the session monitor"
)
vim.api.nvim_win_close(closed_background_win, true)
vim.api.nvim_buf_delete(closed_background_buf, { force = true })

local ui_specs = dofile(vim.fs.joinpath(nvim_root, "lua/plugins/ui.lua"))
local dropbar_spec = vim.iter(ui_specs):find(function(spec)
	return spec[1] == "Bekaboo/dropbar.nvim"
end)
assert(dropbar_spec and dropbar_spec.opts and dropbar_spec.opts.bar, "source Dropbar spec is missing")
assert(dropbar_spec.opts.bar.enable(source_buf, source_float) == true, "source Dropbar spec must allow popup children")
assert(dropbar_spec.opts.bar.enable(vim.api.nvim_win_get_buf(root_float), root_float) == false)

local minimap_specs = dofile(vim.fs.joinpath(nvim_root, "lua/plugins/minimap.lua"))
local is_code_window = upvalue(upvalue(minimap_specs[1].config, "setup_code_layout"), "is_code_window")
assert(is_code_window(source_float) == true, "source minimap spec must allow the worktree child")
assert(is_code_window(revision_float) == false, "source minimap spec must reject the revision child")
assert(is_code_window(source_win) == false, "source minimap spec must reject the underlay")

local arbitrary_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(arbitrary_buf, 0, -1, false, { "arbitrary normal float" })
vim.bo[arbitrary_buf].filetype = "lua"
local arbitrary_float = vim.api.nvim_open_win(arbitrary_buf, false, {
	relative = "editor",
	row = 1,
	col = 1,
	width = 24,
	height = 2,
	style = "minimal",
})
assert(vim.w[arbitrary_float].dotfiles_git_diff_peek_child ~= true)
assert(dropbar_spec.opts.bar.enable(arbitrary_buf, arbitrary_float) == false)
assert(is_code_window(arbitrary_float) == false)
vim.api.nvim_win_close(arbitrary_float, true)
vim.api.nvim_buf_delete(arbitrary_buf, { force = true })

local bar = require("dropbar.utils.bar")
local rendered_source
local rendered_revision
assert(
	vim.wait(1000, function()
		rendered_source = rendered_winbar(source_float)
		rendered_revision = rendered_winbar(revision_float)
		return rendered_source ~= "" and rendered_revision ~= "" and bar.get({ win = source_float }) ~= nil
	end, 20),
	"popup worktree Dropbar and revision breadcrumb wrapper must render"
)
assert(rendered_source ~= "", "the worktree popup must render Dropbar breadcrumbs")
local expected_revision_breadcrumb = " 󰉋 .git  󰈔 :0:   dotfiles-git-diff-peek.lua "
local function revision_breadcrumb_for_focus(focus_win)
	vim.api.nvim_set_current_win(focus_win)
	assert(
		vim.wait(1000, function()
			return vim.wo[revision_float].winbar:find("revision_winbar", 1, true) ~= nil
		end, 20),
		"scheduled style refresh did not restore the revision breadcrumb wrapper"
	)
	local previous_statusline_winid = vim.g.statusline_winid
	vim.g.statusline_winid = revision_float
	local raw = peek.revision_winbar()
	vim.g.statusline_winid = previous_statusline_winid
	return raw, rendered_winbar(revision_float)
end

local inactive_raw, inactive_rendered = revision_breadcrumb_for_focus(source_float)
local active_raw, active_rendered = revision_breadcrumb_for_focus(revision_float)
vim.api.nvim_set_current_win(source_float)
assert(inactive_raw:find("DropBarIconKindFolderNC", 1, true), "inactive folder icon must use its NC group")
assert(inactive_raw:find("DropBarKindDirNC", 1, true), "inactive .git name must use the directory NC group")
assert(inactive_raw:find("DropBarIconUISeparatorNC", 1, true), "inactive separators must use NC groups")
assert(inactive_raw:find("DropBarKindFileNC", 1, true), "inactive file names must use their NC group")
assert(active_raw:find("DropBarIconKindFolder", 1, true), "active folder icon must use its active group")
assert(active_raw:find("DropBarKindDir", 1, true), "active .git name must use the directory group")
assert(active_raw:find("DropBarIconUISeparator", 1, true), "active separators must use active groups")
assert(active_raw:find("DropBarKindFile", 1, true), "active file names must use their active group")
assert(not active_raw:find("NC", 1, true), "active revision breadcrumb must not use NC groups")
assert(
	not inactive_raw:find("DropBarIconKindFile", 1, true) and not active_raw:find("DropBarIconKindFile", 1, true),
	"the :0: icon must inherit WinBar highlighting without an explicit group"
)
assert(
	inactive_raw:find("DevIconLua", 1, true) and active_raw:find("DevIconLua", 1, true),
	"the basename icon must retain its devicon highlight in both focus states"
)
assert(
	inactive_rendered == expected_revision_breadcrumb and active_rendered == expected_revision_breadcrumb,
	("revision breadcrumb mismatch: inactive=%q active=%q width=%d"):format(
		inactive_rendered,
		active_rendered,
		vim.api.nvim_win_get_width(revision_float)
	)
)

local function popup_minimap_ready()
	local minimaps = visible_minimap_windows()
	if #minimaps ~= 1 then
		return false
	end
	local native = mini_map.current.win_data[tab]
	if not native or not vim.api.nvim_win_is_valid(native) then
		return false
	end
	local minimap_config = vim.api.nvim_win_get_config(minimaps[1])
	local native_config = vim.api.nvim_win_get_config(native)
	local child_config = vim.api.nvim_win_get_config(source_float)
	local child_position = vim.api.nvim_win_get_position(source_float)
	local root_config = vim.api.nvim_win_get_config(root_float)
	local child_text_right = child_position[2] + 1 + vim.api.nvim_win_get_width(source_float)
	local root_text_right = root_config.col + 1 + vim.api.nvim_win_get_width(root_float)
	return minimap_config.width == 12
		and minimap_config.zindex > (child_config.zindex or 0)
		and minimap_config.row == child_position[1]
		and minimap_config.height > 0
		and minimap_config.height <= vim.api.nvim_win_get_height(source_float)
		and minimap_config.col + minimap_config.width == child_text_right
		and minimap_config.col + minimap_config.width == root_text_right
		and native_config.hide == true
		and native_config.anchor == "NE"
		and native_config.col == child_text_right
		and native_config.height == vim.api.nvim_win_get_height(source_float)
		and native_config.zindex > (child_config.zindex or 0)
end

assert(vim.wait(2000, popup_minimap_ready, 20), "popup minimap display/native geometry did not stabilize")
assert(#visible_minimap_windows() == 1, "popup must have exactly one visible minimap")
local popup_minimap_width = vim.api.nvim_win_get_config(visible_minimap_windows()[1]).width
local pane_width_delta = math.abs(
	vim.api.nvim_win_get_width(revision_float) - (vim.api.nvim_win_get_width(source_float) - popup_minimap_width)
)
assert(
	pane_width_delta <= 1,
	("popup pane balance mismatch: revision=%d worktree=%d minimap=%d delta=%d"):format(
		vim.api.nvim_win_get_width(revision_float),
		vim.api.nvim_win_get_width(source_float),
		popup_minimap_width,
		pane_width_delta
	)
)
assert(vim.api.nvim_win_get_config(visible_minimap_windows()[1]).zindex > cover_config.zindex)
assert(vim.api.nvim_win_get_config(mini_map.current.win_data[tab]).zindex > cover_config.zindex)

local immediate_style = common_style_snapshot(source_float)
vim.wait(1200, function()
	return false
end, 20)
assert(
	vim.deep_equal(common_style_snapshot(source_float), immediate_style),
	"delayed popup lifecycle changed worktree common chrome"
)
assert(
	vim.deep_equal(common_style_snapshot(revision_float), common_style_snapshot(source_float)),
	"delayed popup common chrome parity drifted"
)
assert(winhighlight_target(source_float, "Normal") == winhighlight_target(revision_float, "Normal"))
assert(winhighlight_target(source_float, "NormalNC") == winhighlight_target(revision_float, "NormalNC"))
assert(winhighlight_target(source_float, "WinBar") == winhighlight_target(revision_float, "WinBar"))
assert(winhighlight_target(source_float, "WinBarNC") == winhighlight_target(revision_float, "WinBarNC"))
assert(winhighlight_target(source_float, "DiffChange") == "DiffviewDiffChangeAdd")
assert(winhighlight_target(source_float, "DiffText") == "DiffviewDiffTextAdd")
assert(winhighlight_target(source_float, "DiffDelete") == "DiffviewDiffDeleteDim")
assert(winhighlight_target(revision_float, "DiffChange") == "DiffviewDiffChangeDelete")
assert(winhighlight_target(revision_float, "DiffText") == "DiffviewDiffTextDelete")
assert(winhighlight_target(revision_float, "DiffDelete") == "DiffviewDiffDeleteDim")
assert(vim.w[source_float].dotfiles_disable_minimap == false)
assert(vim.w[revision_float].dotfiles_disable_minimap == true)

local close_map = vim.iter(vim.api.nvim_buf_get_keymap(source_buf, "n")):find(function(mapping)
	return mapping.desc == "Close Git diff peek"
end)
assert(close_map, "the popup must install its temporary close mapping")

local underlay_callback_observed
local callback_tab_count = #vim.api.nvim_list_tabpages()
assert(
	peek.with_underlay(function()
		underlay_callback_observed = {
			current = vim.api.nvim_get_current_win(),
			children = #vim.tbl_filter(function(win)
				return vim.w[win].dotfiles_git_diff_peek_child == true
			end, vim.api.nvim_tabpage_list_wins(0)),
			tabs = #vim.api.nvim_list_tabpages(),
			appearance = underlay_appearance(source_win),
		}
	end),
	"with_underlay must close an active Git diff peek"
)
assert(
	vim.wait(1000, function()
		return underlay_callback_observed ~= nil
	end, 20),
	"with_underlay callback did not run"
)
assert(underlay_callback_observed.current == source_win, "with_underlay callback must focus the source editor")
assert(underlay_callback_observed.children == 0, "with_underlay callback must run after popup children close")
assert(underlay_callback_observed.tabs == callback_tab_count, "with_underlay callback must not create a tabpage")
assert(
	vim.deep_equal(underlay_callback_observed.appearance, baseline_underlay_appearance),
	"with_underlay callback must observe the restored underlay appearance"
)
peek.toggle()
assert(
	vim.wait(1000, function()
		return popup_child_for(source_buf) ~= nil
	end, 20),
	"with_underlay fixture did not reopen the popup"
)
source_float = assert(popup_child_for(source_buf))

peek.toggle()
assert(diffthis_bases[1] == "HEAD", "ordinary Git diff peek must compare the worktree against HEAD")
local close_observed
assert(
	vim.wait(1000, function()
		close_observed = {
			appearance = underlay_appearance(source_win),
			buf = vim.api.nvim_win_get_buf(source_win),
			current = vim.api.nvim_get_current_win(),
			scratch_valid = vim.api.nvim_buf_is_valid(underlay_scratch),
		}
		return close_observed.current == source_win
			and vim.iter(vim.api.nvim_list_wins()):all(function(win)
				return vim.api.nvim_win_get_config(win).relative == "" or not vim.wo[win].diff
			end)
			and vim.iter(vim.api.nvim_buf_get_keymap(source_buf, "n")):all(function(mapping)
				return mapping.desc ~= "Close Git diff peek"
			end)
			and vim.deep_equal(close_observed.appearance, baseline_underlay_appearance)
	end),
	("closing the popup must restore the source editor: observed=%s expected=%s"):format(
		vim.inspect(close_observed),
		vim.inspect(baseline_underlay_appearance)
	)
)
assert(
	vim.iter(vim.api.nvim_buf_get_keymap(source_buf, "n")):all(function(mapping)
		return mapping.desc ~= "Close Git diff peek"
	end),
	"the popup close mapping must be removed from the source buffer"
)
assert(
	vim.w[source_win].dotfiles_git_diff_peek_underlay == original_underlay_flag,
	"underlay ownership flag was not restored"
)
assert(vim.w[source_win].dotfiles_disable_minimap == original_disable_minimap, "underlay minimap flag was not restored")
assert(vim.b[source_buf].dotfiles_disable_hlchunk == original_hlchunk, "underlay hlchunk flag was not restored")
assert(vim.api.nvim_win_get_buf(source_win) == source_buf, "popup cleanup did not restore the source buffer")
assert(not vim.api.nvim_buf_is_valid(underlay_scratch), "popup cleanup did not wipe the underlay scratch")
assert(not vim.api.nvim_win_is_valid(cover_float), "popup cleanup left the full-editor cover visible")
assert(not vim.api.nvim_buf_is_valid(cover_buf), "popup cleanup leaked the full-editor cover buffer")
assert(vim.o.laststatus == baseline_laststatus, "popup cleanup did not restore the global statusline policy")
for _, background in ipairs({
	{ win = background_float_a, buf = background_float_buf_a, config = background_float_config_a },
	{ win = background_float_b, buf = background_float_buf_b, config = background_float_config_b },
}) do
	assert(vim.api.nvim_win_is_valid(background.win) and vim.api.nvim_buf_is_valid(background.buf))
	assert(vim.api.nvim_win_get_buf(background.win) == background.buf)
	assert(vim.deep_equal(vim.api.nvim_win_get_config(background.win), background.config))
end
vim.cmd.redraw({ bang = true })
assert(
	screen_row(expected_cover_top + 1):find("FLOAT-A-CONTENT", 1, true),
	"popup cleanup did not reveal the unchanged background float"
)
assert(
	vim.deep_equal(vim.api.nvim_win_call(source_win, vim.fn.winsaveview), baseline_source_view),
	"popup cleanup did not restore the source view"
)
assert(alternate_buffer(source_win) == baseline_alternate_buf, "popup cleanup changed the alternate buffer")
assert(
	vim.api.nvim_buf_get_lines(source_buf, 0, -1, false)[3] == "return value",
	"popup cleanup changed buffer content"
)
assert(vim.api.nvim_win_get_cursor(source_win)[1] == 3, "popup cleanup changed the source cursor")
assert(vim.wo[source_win].sidescrolloff == baseline_sidescrolloff, "popup cleanup accumulated minimap margin")
assert(
	vim.w[background_win].dotfiles_disable_minimap == false,
	"popup cleanup did not restore the background editor minimap flag exactly"
)
assert(vim.w[disabled_background_win].dotfiles_disable_minimap == true)
assert(
	vim.w[during_popup_win].dotfiles_disable_minimap == nil,
	"popup cleanup did not restore an unset background editor minimap flag"
)
assert(
	background_minimap_monitor_count() == baseline_monitor_count,
	"popup cleanup leaked its session background minimap monitor"
)
assert(
	snapshot_resize_monitor_count() == baseline_snapshot_monitor_count,
	"popup cleanup leaked its frozen background resize monitor"
)
assert(
	vim.wait(1500, function()
		return #visible_minimap_windows() == 3
	end, 20),
	"popup cleanup did not restore multi-editor minimap ownership"
)
for _, window in ipairs({
	{ win = background_win, buf = background_buf },
	{ win = disabled_background_win, buf = disabled_background_buf },
	{ win = during_popup_win, buf = during_popup_buf },
	{ win = background_float_a, buf = background_float_buf_a },
	{ win = background_float_b, buf = background_float_buf_b },
}) do
	vim.api.nvim_win_close(window.win, true)
	vim.api.nvim_buf_delete(window.buf, { force = true })
end

local post_close_win, post_close_buf = create_background_split("/tmp/dotfiles-git-diff-peek-post-close.lua", nil)
vim.wait(100, function()
	return false
end, 20)
assert(
	vim.w[post_close_win].dotfiles_disable_minimap == nil,
	"a closed popup continued to mutate newly created background editors"
)
vim.api.nvim_win_close(post_close_win, true)
vim.api.nvim_buf_delete(post_close_buf, { force = true })
mini_map.refresh({}, { layout = true, integrations = false, lines = false, scrollbar = false })
local restored_native_config
local restored_display_config
local restored_minimap_count = 0
local geometry_restored = vim.wait(1500, function()
	local native = mini_map.current.win_data[tab]
	local minimaps = visible_minimap_windows()
	restored_minimap_count = #minimaps
	if not native or not vim.api.nvim_win_is_valid(native) or #minimaps ~= 1 then
		return false
	end
	restored_native_config = vim.deepcopy(vim.api.nvim_win_get_config(native))
	restored_display_config = vim.deepcopy(vim.api.nvim_win_get_config(minimaps[1]))
	return vim.deep_equal(restored_native_config, baseline_native_config)
		and vim.deep_equal(restored_display_config, baseline_display_config)
end, 20)
assert(
	geometry_restored,
	("popup cleanup did not restore ordinary minimap ownership and geometry: count=%d native=%s/%s display=%s/%s"):format(
		restored_minimap_count,
		vim.inspect(restored_native_config),
		vim.inspect(baseline_native_config),
		vim.inspect(restored_display_config),
		vim.inspect(baseline_display_config)
	)
)
assert(vim.wo[source_win].sidescrolloff == baseline_sidescrolloff, "ordinary minimap margin changed after close")

vim.api.nvim_set_current_win(source_win)
peek.toggle()
assert(
	vim.wait(1000, function()
		return #vim.tbl_filter(function(win)
			return vim.w[win].dotfiles_git_diff_peek_child == true
		end, vim.api.nvim_tabpage_list_wins(0)) == 2
	end, 20),
	"the session identity fixture did not open its first popup"
)
peek.toggle()
defer_diff_callback = true
local reopen_hl_ns = vim.api.nvim_create_namespace("dotfiles-git-diff-peek-reopen-sentinel")
vim.api.nvim_set_hl(reopen_hl_ns, "Normal", { fg = "#eeeeee", bg = "#112233" })
local latest_reopen_appearance
local reopen_finished = false
local reopen_error
vim.api.nvim_create_autocmd("BufWinEnter", {
	buffer = source_buf,
	once = true,
	callback = function()
		vim.schedule(function()
			local ok, err = xpcall(function()
				vim.api.nvim_set_current_win(source_win)
				for name, value in pairs(baseline_underlay_appearance.options) do
					vim.api.nvim_set_option_value(name, value, { scope = "local", win = source_win })
				end
				vim.api.nvim_win_set_hl_ns(source_win, reopen_hl_ns)
				vim.wo[source_win].colorcolumn = "13"
				vim.wo[source_win].cursorcolumn = false
				vim.wo[source_win].foldcolumn = "2"
				latest_reopen_appearance = underlay_appearance(source_win)
				peek.toggle()
			end, debug.traceback)
			reopen_error = not ok and err or nil
			reopen_finished = true
		end)
	end,
})
assert(
	vim.wait(1000, function()
		assert(not reopen_error, reopen_error)
		return reopen_finished and type(pending_diff_callback) == "function"
	end, 20),
	"the cleanup interleaving fixture did not create its replacement pending session"
)
vim.wait(100, function()
	return false
end, 20)
assert(vim.api.nvim_get_hl_ns({ winid = source_win }) == reopen_hl_ns)
assert(vim.wo[source_win].colorcolumn == "13" and not vim.wo[source_win].cursorcolumn)
assert(
	vim.iter(vim.api.nvim_tabpage_list_wins(0)):all(function(win)
		return vim.w[win].dotfiles_git_diff_peek_child ~= true and vim.w[win].dotfiles_git_diff_peek_cover ~= true
	end),
	"the replacement pending session opened popup children or a cover before its callback"
)
defer_diff_callback = false
pending_diff_callback()
pending_diff_callback = nil
assert(
	vim.wait(1000, function()
		local children = vim.tbl_filter(function(win)
			return vim.w[win].dotfiles_git_diff_peek_child == true
		end, vim.api.nvim_tabpage_list_wins(0))
		local covers = vim.tbl_filter(function(win)
			return vim.w[win].dotfiles_git_diff_peek_cover == true
		end, vim.api.nvim_tabpage_list_wins(0))
		return #children == 2
			and #covers == 1
			and vim.api.nvim_get_hl_ns({ winid = source_win }) == underlay_namespace
			and vim.api.nvim_win_get_buf(source_win) ~= source_buf
	end, 20),
	"the replacement pending session did not become a transparent active popup"
)
assert(not vim.wo[source_win].cursorcolumn and vim.wo[source_win].foldcolumn == "0")
assert(vim.wo[source_win].colorcolumn == "")
peek.toggle()
assert(
	vim.wait(1000, function()
		return vim.api.nvim_win_get_buf(source_win) == source_buf
			and vim.deep_equal(underlay_appearance(source_win), latest_reopen_appearance)
			and vim.iter(vim.api.nvim_tabpage_list_wins(0)):all(function(win)
				return vim.w[win].dotfiles_git_diff_peek_cover ~= true
			end)
	end, 20),
	"the reopened popup did not restore its latest pre-open appearance snapshot"
)
for name, value in pairs(baseline_underlay_appearance.options) do
	vim.api.nvim_set_option_value(name, value, { scope = "local", win = source_win })
end
vim.api.nvim_win_set_hl_ns(source_win, baseline_underlay_appearance.hl_ns)

local expanded_lines = { "local value = 1" }
for line = 2, 79 do
	expanded_lines[line] = ("local unchanged_%d = %d"):format(line, line)
end
expanded_lines[80] = "return value"
vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, expanded_lines)
vim.api.nvim_win_set_cursor(source_win, { 40, 0 })
defer_diff_callback = true
peek.toggle()
assert(type(pending_diff_callback) == "function", "the fixture must defer Gitsigns popup creation")

local pending_zr = vim.iter(vim.api.nvim_buf_get_keymap(source_buf, "n")):find(function(mapping)
	return vim.keycode(mapping.lhs) == vim.keycode("zR") and mapping.desc == "Open pending Git diff folds"
end)
assert(pending_zr and type(pending_zr.callback) == "function", "pending popup creation must capture an early zR")
pending_zr.callback()
pending_diff_callback()
pending_diff_callback = nil

local expanded_children = {}
assert(
	vim.wait(1000, function()
		expanded_children = vim.tbl_filter(function(win)
			return vim.w[win].dotfiles_git_diff_peek_child == true
		end, vim.api.nvim_tabpage_list_wins(0))
		return #expanded_children == 2
	end, 20),
	"the deferred Gitsigns callback must create both popup children"
)

local function first_closed_fold(win)
	return vim.api.nvim_win_call(win, function()
		for line = 1, vim.api.nvim_buf_line_count(0) do
			if vim.fn.foldclosed(line) > 0 then
				return line
			end
		end
		return -1
	end)
end

for _, win in ipairs(expanded_children) do
	local zr = vim.iter(vim.api.nvim_buf_get_keymap(vim.api.nvim_win_get_buf(win), "n")):find(function(mapping)
		return vim.keycode(mapping.lhs) == vim.keycode("zR") and mapping.desc == "Open all Git diff folds"
	end)
	assert(zr and type(zr.callback) == "function", "both popup children must expose the explicit zR action")
	assert(vim.wo[win].foldlevel > 0 and first_closed_fold(win) == -1, "an early zR must open every popup fold")
end

local expanded_foldlevels = vim.tbl_map(function(win)
	return vim.wo[win].foldlevel
end, expanded_children)
vim.api.nvim_exec_autocmds("WinEnter", { modeline = false })
vim.api.nvim_exec_autocmds("ModeChanged", { modeline = false, pattern = "n:i" })
vim.wait(200, function()
	return false
end, 20)
for index, win in ipairs(expanded_children) do
	assert(
		vim.wo[win].foldlevel == expanded_foldlevels[index] and first_closed_fold(win) == -1,
		"reapplying Gitsigns chrome must preserve the user-expanded fold state"
	)
end

for _, win in ipairs(expanded_children) do
	vim.api.nvim_win_call(win, function()
		vim.cmd.normal({ args = { "zM" }, bang = true })
	end)
end
local revision_child = vim.iter(expanded_children):find(function(win)
	return vim.w[win].dotfiles_git_diff_peek_role == "revision"
end)
assert(revision_child, "the expanded popup must retain its revision child")
local revision_zr = vim.iter(vim.api.nvim_buf_get_keymap(vim.api.nvim_win_get_buf(revision_child), "n"))
	:find(function(mapping)
		return vim.keycode(mapping.lhs) == vim.keycode("zR") and mapping.desc == "Open all Git diff folds"
	end)
vim.api.nvim_set_current_win(revision_child)
revision_zr.callback()
for _, win in ipairs(expanded_children) do
	assert(vim.wo[win].foldlevel > 0 and first_closed_fold(win) == -1, "zR from either child must open both panes")
end

peek.toggle()
assert(
	vim.wait(1000, function()
		return vim.api.nvim_get_current_win() == source_win
			and vim.iter(vim.api.nvim_buf_get_keymap(source_buf, "n")):all(function(mapping)
				return mapping.desc ~= "Open pending Git diff folds" and mapping.desc ~= "Open all Git diff folds"
			end)
			and vim.wo[source_win].sidescrolloff == baseline_sidescrolloff
	end, 20),
	"closing an expanded popup must remove both temporary zR mappings"
)

defer_diff_callback = false
local replacement_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(replacement_buf, 0, -1, false, { "user-selected underlay buffer" })
peek.toggle()
local abandoned_scratch = vim.api.nvim_win_get_buf(source_win)
assert(abandoned_scratch ~= source_buf, "the overwrite guard fixture must start with a detached underlay")
vim.api.nvim_win_set_buf(source_win, replacement_buf)
local replacement_margin_base = vim.wo[source_win].sidescrolloff
peek.toggle()
local replacement_observed
assert(
	vim.wait(1000, function()
		local manager = mini_map._dotfiles_multi_window_manager
		local state = manager.source_margins[source_win]
		local map_win = manager.map_window_for_source(source_win)
		replacement_observed = {
			appearance = underlay_appearance(source_win),
			buf = vim.api.nvim_win_get_buf(source_win),
			margin_state = state,
			map_win = map_win,
			sidescrolloff = vim.wo[source_win].sidescrolloff,
			underlay_flag = vim.w[source_win].dotfiles_git_diff_peek_underlay,
		}
		return vim.api.nvim_win_get_buf(source_win) == replacement_buf
			and vim.w[source_win].dotfiles_git_diff_peek_underlay == original_underlay_flag
			and vim.deep_equal(underlay_appearance(source_win), baseline_underlay_appearance)
			and state == nil
			and map_win == nil
			and vim.wo[source_win].sidescrolloff == replacement_margin_base
	end, 20),
	("popup cleanup must not overwrite a buffer selected in the underlay: %s"):format(vim.inspect(replacement_observed))
)
assert(not vim.api.nvim_buf_is_valid(abandoned_scratch), "an abandoned underlay scratch must be wiped")
assert(vim.w[source_win].dotfiles_disable_minimap == original_disable_minimap)
assert(vim.b[source_buf].dotfiles_disable_hlchunk == original_hlchunk)

vim.api.nvim_set_current_win(source_win)
vim.api.nvim_win_set_buf(source_win, source_buf)
local failure_view = vim.api.nvim_win_call(source_win, vim.fn.winsaveview)
local failure_alternate = alternate_buffer(source_win)
local failure_underlay_appearance = underlay_appearance(source_win)
local snacks = require("snacks")
local original_layout_new = snacks.layout.new
local failed_scratch
local failed_cover_win
local failed_cover_buf
snacks.layout.new = function(opts)
	local layout = original_layout_new(opts)
	local original_layout_show = layout.show
	layout.show = function(self)
		original_layout_show(self)
		failed_scratch = vim.api.nvim_win_get_buf(source_win)
		failed_cover_win = assert(self.root.backdrop and self.root.backdrop.win)
		failed_cover_buf = vim.api.nvim_win_get_buf(failed_cover_win)
		error("intentional layout failure")
	end
	return layout
end
peek.toggle()
snacks.layout.new = original_layout_new
assert(failed_scratch and failed_scratch ~= source_buf, "layout failure must occur after underlay detachment")
local failure_observed
assert(
	vim.wait(1000, function()
		failure_observed = {
			appearance = underlay_appearance(source_win),
			buf = vim.api.nvim_win_get_buf(source_win),
			sidescrolloff = vim.wo[source_win].sidescrolloff,
			underlay_flag = vim.w[source_win].dotfiles_git_diff_peek_underlay,
		}
		return vim.api.nvim_win_get_buf(source_win) == source_buf
			and vim.w[source_win].dotfiles_git_diff_peek_underlay == original_underlay_flag
			and vim.deep_equal(underlay_appearance(source_win), failure_underlay_appearance)
	end, 20),
	("layout failure did not restore the source underlay: %s"):format(vim.inspect(failure_observed))
)
assert(not vim.api.nvim_buf_is_valid(failed_scratch), "layout failure did not wipe the underlay scratch")
assert(not vim.api.nvim_win_is_valid(failed_cover_win), "layout failure left the full-editor cover visible")
assert(not vim.api.nvim_buf_is_valid(failed_cover_buf), "layout failure leaked the full-editor cover buffer")
assert(vim.deep_equal(vim.api.nvim_win_call(source_win, vim.fn.winsaveview), failure_view))
assert(alternate_buffer(source_win) == failure_alternate, "layout failure changed the alternate buffer")
assert(vim.w[source_win].dotfiles_disable_minimap == original_disable_minimap)
assert(vim.b[source_buf].dotfiles_disable_hlchunk == original_hlchunk)
assert(vim.wo[source_win].sidescrolloff == baseline_sidescrolloff, "failure cleanup accumulated minimap margin")
assert(vim.o.laststatus == baseline_laststatus, "layout failure leaked the global statusline policy")
assert(snapshot_resize_monitor_count() == baseline_snapshot_monitor_count)
assert(
	vim.iter(vim.api.nvim_tabpage_list_wins(0)):all(function(win)
		return not vim.startswith(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)), "gitsigns://")
	end),
	"layout failure left a Gitsigns revision window behind"
)

local diff_context = require("config.git_diff_context")
local added_file_revision = diff_context.added_file_revision
diff_context.added_file_revision = function(_, base)
	return { base = base, git_dir = "/tmp/.git", relpath = "dotfiles-git-diff-peek.lua" }
end
peek.toggle()
assert(
	vim.wait(1000, function()
		return #vim.tbl_filter(function(win)
			return vim.w[win].dotfiles_git_diff_peek_child == true
		end, vim.api.nvim_tabpage_list_wins(0)) == 2
	end, 20),
	"an added file did not open against an empty revision"
)
local empty_revision = vim.iter(vim.api.nvim_list_bufs()):find(function(buf)
	return vim.startswith(vim.api.nvim_buf_get_name(buf), "gitsigns:///tmp/.git//HEAD:")
end)
assert(empty_revision, "an added file did not receive a Git revision buffer")
assert(
	vim.deep_equal(vim.api.nvim_buf_get_lines(empty_revision, 0, -1, false), { "" }),
	"an added file must compare against an empty revision"
)
peek.toggle()
diff_context.added_file_revision = added_file_revision
assert(vim.o.laststatus == baseline_laststatus, "closing an added-file popup leaked the global statusline policy")

defer_diff_callback = true
peek.toggle()
assert(type(pending_diff_callback) == "function", "the cancellation fixture must leave Gitsigns pending")
assert(vim.o.laststatus == 3, "a pending popup must already expose the global statusline")
peek.toggle()
assert(vim.o.laststatus == baseline_laststatus, "cancelling a pending popup leaked the global statusline policy")
defer_diff_callback = false
pending_diff_callback()
pending_diff_callback = nil
assert(vim.o.laststatus == baseline_laststatus, "a stale Gitsigns callback changed the restored statusline policy")

local diffthis = package.loaded.gitsigns.diffthis
package.loaded.gitsigns.diffthis = function()
	error("synchronous Gitsigns failure")
end
peek.toggle()
package.loaded.gitsigns.diffthis = diffthis
assert(
	vim.iter(vim.api.nvim_buf_get_keymap(source_buf, "n")):all(function(mapping)
		return mapping.desc ~= "Open pending Git diff folds"
	end),
	"a synchronous Gitsigns failure must remove the pending zR mapping"
)
assert(vim.o.laststatus == baseline_laststatus, "a synchronous Gitsigns failure leaked the statusline policy")

vim.api.nvim_set_current_win(source_win)
vim.api.nvim_win_set_buf(source_win, source_buf)
vim.wait(100, function()
	return false
end, 20)
pcall(vim.api.nvim_del_augroup_by_name, "dotfiles-buffer-cycle-keymaps")
local recursive_sentinel = function() end
vim.keymap.set("n", "]]", recursive_sentinel, {
	buffer = source_buf,
	desc = "Recursive next buffer sentinel",
	remap = true,
})
peek.toggle()
assert(
	vim.wait(1000, function()
		return popup_child_for(source_buf) ~= nil
	end, 20),
	"recursive-map fixture did not open a popup"
)
peek.toggle()
local restored_recursive_map
assert(
	vim.wait(1000, function()
		restored_recursive_map = buffer_map(source_buf, "]]", "Recursive next buffer sentinel")
		return restored_recursive_map ~= nil and restored_recursive_map.callback == recursive_sentinel
	end, 20),
	("recursive next-buffer mapping was not restored after popup close: %s"):format(
		vim.inspect(vim.api.nvim_buf_get_keymap(source_buf, "n"))
	)
)
assert(restored_recursive_map.noremap == 0, "recursive next-buffer mapping was restored as non-recursive")

local redirect_win, redirect_buf = create_background_split("/tmp/dotfiles-git-diff-peek-navigation-redirect.lua", false)
vim.api.nvim_set_current_win(source_win)
peek.toggle()
assert(
	vim.wait(1000, function()
		return popup_child_for(source_buf) ~= nil
	end, 20),
	"focus-redirect fixture did not open a popup"
)
local redirected_old_popup = assert(popup_child_for(source_buf))
local redirect_command_count = #navigation_commands
navigation_focus_redirect = redirect_win
assert(popup_map(redirected_old_popup, "]]", "Next Git diff peek buffer")).callback()
assert(
	vim.wait(1000, function()
		return not vim.api.nvim_win_is_valid(redirected_old_popup)
			and vim.api.nvim_get_current_win() == redirect_win
			and #vim.tbl_filter(function(win)
					return vim.w[win].dotfiles_git_diff_peek_child == true
				end, vim.api.nvim_tabpage_list_wins(0))
				== 0
	end, 20),
	"focus redirect opened a replacement Git diff peek popup or stole focus"
)
assert(#navigation_commands == redirect_command_count + 1, "focus redirect invoked BufferLineCycle more than once")
navigation_focus_redirect = nil
vim.api.nvim_win_close(redirect_win, true)
vim.api.nvim_buf_delete(redirect_buf, { force = true })

local function has_normal_buffer_map(buf, lhs)
	return vim.iter(vim.api.nvim_buf_get_keymap(buf, "n")):any(function(mapping)
		return vim.keycode(mapping.lhs) == vim.keycode(lhs)
	end)
end

assert(not has_normal_buffer_map(source_buf, "gp"), "Git diff peek must not override builtin gp")
assert(not has_normal_buffer_map(source_buf, "ge"), "Git diff peek must not override builtin ge")
vim.api.nvim_set_current_win(source_win)
vim.api.nvim_win_set_buf(source_win, source_buf)
vim.wo[source_win].diff = false
peek.toggle()
assert(
	vim.wait(1000, function()
		return popup_child_for(source_buf) ~= nil
	end, 20),
	"generic worktree fixture did not open a popup"
)
source_float = assert(popup_child_for(source_buf))
vim.api.nvim_buf_set_lines(source_buf, -1, -1, false, { "-- ordinary worktree edit" })
assert(
	vim.api.nvim_buf_get_lines(source_buf, 0, -1, false)[#vim.api.nvim_buf_get_lines(source_buf, 0, -1, false)]
		== "-- ordinary worktree edit",
	"ordinary editing in the worktree pane must edit the real source buffer"
)
assert(has_normal_buffer_map(source_buf, "gp") == false and has_normal_buffer_map(source_buf, "ge") == false)

vim.api.nvim_win_set_cursor(source_float, { 1, 0 })
vim.wait(100, function()
	return false
end, 20)
assert(
	vim.api.nvim_win_is_valid(source_float) and vim.api.nvim_win_get_buf(source_float) == source_buf,
	"same-file cursor movement must not rebuild the diff session"
)

local active_child_zindex = assert(peek.child_ui_zindex(), "an active popup must expose a child UI z-index")

local layered_children = {}
for _, filetype in ipairs({ "glance", "fzf" }) do
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].filetype = filetype
	local win = vim.api.nvim_open_win(buf, false, {
		relative = "editor",
		row = 2,
		col = 2,
		width = 20,
		height = 2,
		style = "minimal",
		zindex = filetype == "fzf" and 50 or 45,
	})
	layered_children[#layered_children + 1] = { win = win, buf = buf }
end

assert(
	vim.wait(1000, function()
		if vim.iter(layered_children):any(function(child)
			return not vim.api.nvim_win_is_valid(child.win)
		end) then
			return false
		end
		local zindexes = vim.tbl_map(function(child)
			return vim.api.nvim_win_get_config(child.win).zindex
		end, layered_children)
		return zindexes[1] == active_child_zindex and zindexes[2] == active_child_zindex + 5
	end, 20),
	"a generic child-float batch must preserve the relative Glance/fzf z-index"
)
for _, child in ipairs(layered_children) do
	vim.api.nvim_win_close(child.win, true)
	vim.api.nvim_buf_delete(child.buf, { force = true })
end
local diagnostic_namespace = vim.api.nvim_create_namespace("dotfiles-git-diff-peek-layering-diagnostic")
vim.diagnostic.set(diagnostic_namespace, source_buf, {
	{ lnum = 0, col = 0, message = "layering diagnostic", severity = vim.diagnostic.severity.WARN },
})
local diagnostic_buf, diagnostic_win = vim.diagnostic.open_float(source_buf, {
	close_events = {},
	focusable = false,
	scope = "line",
})
assert(
	vim.wait(1000, function()
		return vim.api.nvim_win_is_valid(diagnostic_win)
			and vim.api.nvim_win_get_config(diagnostic_win).zindex >= active_child_zindex
	end, 20),
	"a real diagnostic float must be raised above Git diff peek"
)
vim.api.nvim_win_close(diagnostic_win, true)
if vim.api.nvim_buf_is_valid(diagnostic_buf) then
	vim.api.nvim_buf_delete(diagnostic_buf, { force = true })
end
local hover_buf, hover_win = vim.lsp.util.open_floating_preview({ "hover" }, "markdown", {
	close_events = {},
	focus = true,
	zindex = 45,
})
assert(
	vim.wait(1000, function()
		return vim.api.nvim_win_is_valid(hover_win)
			and vim.api.nvim_win_get_config(hover_win).zindex >= active_child_zindex
	end, 20),
	"a real hover float must be raised above Git diff peek"
)
vim.api.nvim_win_close(hover_win, true)
if vim.api.nvim_buf_is_valid(hover_buf) then
	vim.api.nvim_buf_delete(hover_buf, { force = true })
end
assert(popup_child_for(source_buf) == source_float, "cancelling child UI must preserve the worktree session")

local popup_tab = vim.api.nvim_get_current_tabpage()
local function popup_child_count(tab)
	return #vim.tbl_filter(function(win)
		return vim.w[win].dotfiles_git_diff_peek_child == true
	end, vim.api.nvim_tabpage_list_wins(tab))
end
local function reopen_source_popup()
	local existing = popup_child_for(source_buf)
	if existing then
		return existing
	end
	vim.api.nvim_set_current_win(source_win)
	vim.api.nvim_win_set_buf(source_win, source_buf)
	vim.wo[source_win].diff = false
	peek.toggle()
	assert(
		vim.wait(1000, function()
			return popup_child_for(source_buf) ~= nil
		end, 20),
		"boundary fixture did not reopen the source popup"
	)
	return assert(popup_child_for(source_buf))
end
local function assert_controlled_boundary(command, tab_boundary)
	local worktree = reopen_source_popup()
	vim.api.nvim_set_current_win(worktree)
	vim.cmd(command)
	assert(
		vim.wait(1000, function()
			return popup_child_count(popup_tab) == 0 and vim.api.nvim_win_get_buf(source_win) == source_buf
		end, 20),
		command .. " must close Git Diff Peek before leaving a normal editor boundary"
	)
	if tab_boundary then
		vim.cmd("tabclose!")
		assert(vim.api.nvim_get_current_tabpage() == popup_tab, "tab boundary must return to the restored source tab")
	else
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(popup_tab)) do
			if win ~= source_win and vim.api.nvim_win_get_config(win).relative == "" then
				vim.api.nvim_win_close(win, true)
			end
		end
	end
end

-- Glance closes to its parent worktree before running split/tab jumps; fzf file
-- actions likewise execute their standard command after picker close.
assert_controlled_boundary("split", false)
assert_controlled_boundary("vsplit", false)
assert_controlled_boundary("new", false)
assert_controlled_boundary("tabnew", true)
source_float = reopen_source_popup()

local intermediate_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(intermediate_buf, "/tmp/dotfiles-git-diff-peek-intermediate.lua")
vim.api.nvim_buf_set_lines(intermediate_buf, 0, -1, false, { "local intermediate = true" })
vim.bo[intermediate_buf].filetype = "lua"
local cross_file_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(cross_file_buf, "/tmp/dotfiles-git-diff-peek-cross-file.lua")
vim.api.nvim_buf_set_lines(cross_file_buf, 0, -1, false, { "local cross_file = true" })
vim.bo[cross_file_buf].filetype = "lua"
vim.api.nvim_win_set_buf(source_float, intermediate_buf)
vim.api.nvim_win_set_buf(source_float, cross_file_buf)
assert(
	vim.wait(1000, function()
		local child = popup_child_for(cross_file_buf)
		return not vim.api.nvim_win_is_valid(source_float)
			and child ~= nil
			and child ~= source_float
			and vim.api.nvim_get_current_win() == child
			and popup_child_for(intermediate_buf) == nil
	end, 20),
	"same-tick cross-file worktree navigation must reopen only the final target session"
)
local cross_file_float = assert(popup_child_for(cross_file_buf))
assert(vim.wo[cross_file_float].diff, "cross-file worktree pane must remain a diff pane")
vim.api.nvim_buf_delete(intermediate_buf, { force = true })
vim.api.nvim_set_current_win(cross_file_float)
peek.toggle()
local cross_file_cleanup
assert(
	vim.wait(1000, function()
		cross_file_cleanup = {
			current = vim.api.nvim_get_current_win(),
			source_buf = vim.api.nvim_win_get_buf(source_win),
			children = #vim.tbl_filter(function(win)
				return vim.w[win].dotfiles_git_diff_peek_child == true
			end, vim.api.nvim_tabpage_list_wins(0)),
		}
		return cross_file_cleanup.current == source_win and cross_file_cleanup.source_buf == cross_file_buf
	end, 20),
	("cross-file popup cleanup must restore the selected target editor: %s"):format(vim.inspect(cross_file_cleanup))
)

local diff_context = require("config.git_diff_context")
local resolve_base = diff_context.resolve_base
local non_diffable_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(non_diffable_buf, "/tmp/dotfiles-git-diff-peek-non-diffable.lua")
vim.api.nvim_buf_set_lines(non_diffable_buf, 0, -1, false, { "local no_revision = true" })
vim.bo[non_diffable_buf].filetype = "lua"
diff_context.resolve_base = function(buf)
	if buf == non_diffable_buf then
		return nil, "intentional non-diffable target"
	end
	return resolve_base(buf)
end
peek.toggle()
assert(
	vim.wait(1000, function()
		return popup_child_for(cross_file_buf) ~= nil
	end, 20),
	"non-diffable handoff fixture did not reopen the source popup"
)
cross_file_float = assert(popup_child_for(cross_file_buf))
vim.api.nvim_win_set_buf(cross_file_float, non_diffable_buf)
assert(
	vim.wait(1000, function()
		return vim.api.nvim_get_current_win() == source_win
			and vim.api.nvim_win_get_buf(source_win) == non_diffable_buf
			and #vim.tbl_filter(function(win)
					return vim.w[win].dotfiles_git_diff_peek_child == true
				end, vim.api.nvim_tabpage_list_wins(0))
				== 0
	end, 20),
	"a non-diffable target must remain a normal editor without stale popup panes"
)
diff_context.resolve_base = resolve_base
assert(not has_normal_buffer_map(non_diffable_buf, "gp") and not has_normal_buffer_map(non_diffable_buf, "ge"))
assert(
	vim.iter(vim.api.nvim_buf_get_keymap(cross_file_buf, "n")):all(function(mapping)
		return mapping.desc ~= "Close Git diff peek"
	end),
	"cross-file cleanup must remove temporary popup mappings"
)
vim.api.nvim_buf_delete(cross_file_buf, { force = true })
vim.api.nvim_buf_delete(non_diffable_buf, { force = true })
assert(
	vim.iter(vim.api.nvim_get_autocmds({})):all(function(autocmd)
		return autocmd.desc ~= "Git diff peek worktree buffer handoff"
			and autocmd.desc ~= "Git diff peek worktree split boundary"
			and autocmd.desc ~= "Git diff peek child float layering"
			and autocmd.desc ~= "Git diff peek tab boundary"
	end),
	"Git diff peek cleanup must remove its transition autocmds and augroup"
)

print("Git diff peek popup regression: ok")
