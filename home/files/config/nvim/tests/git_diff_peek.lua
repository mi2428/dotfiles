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
vim.o.columns = 190
vim.o.lines = 65

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

local defer_diff_callback = false
local pending_diff_callback
local mutate_source_statuscolumn = false
local mutate_popup_revision_statuscolumn = false
package.loaded.gitsigns = {
	diffthis = function(_, _, callback)
		local revision_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(revision_buf, "gitsigns:///tmp/.git//:0:dotfiles-git-diff-peek.lua")
		local revision_lines = vim.api.nvim_buf_get_lines(source_buf, 0, -1, false)
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
assert(
	vim.wait(1500, function()
		local native = mini_map.current.win_data[tab]
		return native and vim.api.nvim_win_is_valid(native) and #visible_minimap_windows() == 1
	end, 20),
	"the fixture must expose one ordinary visible minimap before popup open"
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

local function background_minimap_monitor_count()
	local ids = {}
	for _, autocmd in ipairs(vim.api.nvim_get_autocmds({})) do
		if autocmd.desc == "Git diff peek background minimap ownership" then
			ids[autocmd.id] = true
		end
	end
	return vim.tbl_count(ids)
end

local baseline_monitor_count = background_minimap_monitor_count()
local background_win, background_buf = create_background_split("/tmp/dotfiles-git-diff-peek-background.lua", false)
local disabled_background_win, disabled_background_buf =
	create_background_split("/tmp/dotfiles-git-diff-peek-disabled-background.lua", true)
vim.api.nvim_set_current_win(source_win)
mini_map.refresh({}, { layout = true, integrations = false, lines = false, scrollbar = false })
assert(
	vim.wait(1500, function()
		return #visible_minimap_windows() == 2
	end, 20),
	"the multi-editor fixture must expose a second visible minimap before popup open"
)

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
	end
end

assert(source_float, "the worktree diff pane must be a floating window")
assert(revision_float, "the revision diff pane must be a floating window")
assert(root_float, "the diff panes must have a shared floating layout root")
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
	assert(style.cursorline and style.cursorlineopt == "number", "popup cursorline options mismatch")
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
	return minimap_config.width == 12
		and minimap_config.zindex > (child_config.zindex or 0)
		and minimap_config.row == child_position[1]
		and minimap_config.height > 0
		and minimap_config.height <= vim.api.nvim_win_get_height(source_float)
		and minimap_config.col + minimap_config.width == child_position[2] + vim.api.nvim_win_get_width(source_float)
		and native_config.hide == true
		and native_config.anchor == "NE"
		and native_config.col == child_position[2] + vim.api.nvim_win_get_width(source_float)
		and native_config.height == vim.api.nvim_win_get_height(source_float)
		and native_config.zindex > (child_config.zindex or 0)
end

assert(vim.wait(2000, popup_minimap_ready, 20), "popup minimap display/native geometry did not stabilize")
assert(#visible_minimap_windows() == 1, "popup must have exactly one visible minimap")

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

peek.toggle()
assert(
	vim.wait(1000, function()
		return vim.api.nvim_get_current_win() == source_win
			and vim.iter(vim.api.nvim_list_wins()):all(function(win)
				return vim.api.nvim_win_get_config(win).relative == "" or not vim.wo[win].diff
			end)
			and vim.iter(vim.api.nvim_buf_get_keymap(source_buf, "n")):all(function(mapping)
				return mapping.desc ~= "Close Git diff peek"
			end)
	end),
	"closing the popup must restore the source editor"
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
	vim.wait(1500, function()
		return #visible_minimap_windows() == 3
	end, 20),
	"popup cleanup did not restore multi-editor minimap ownership"
)
for _, window in ipairs({
	{ win = background_win, buf = background_buf },
	{ win = disabled_background_win, buf = disabled_background_buf },
	{ win = during_popup_win, buf = during_popup_buf },
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
assert(
	vim.wait(1500, function()
		local native = mini_map.current.win_data[tab]
		local minimaps = visible_minimap_windows()
		if not native or not vim.api.nvim_win_is_valid(native) or #minimaps ~= 1 then
			return false
		end
		local native_config = vim.api.nvim_win_get_config(native)
		local display_config = vim.api.nvim_win_get_config(minimaps[1])
		return vim.deep_equal(native_config, baseline_native_config)
			and vim.deep_equal(display_config, baseline_display_config)
	end, 20),
	"popup cleanup did not restore ordinary minimap ownership and geometry"
)

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
peek.toggle()
assert(
	vim.wait(1000, function()
		return vim.api.nvim_win_get_buf(source_win) == replacement_buf
			and vim.w[source_win].dotfiles_git_diff_peek_underlay == original_underlay_flag
	end, 20),
	"popup cleanup must not overwrite a buffer selected in the underlay"
)
assert(not vim.api.nvim_buf_is_valid(abandoned_scratch), "an abandoned underlay scratch must be wiped")
assert(vim.w[source_win].dotfiles_disable_minimap == original_disable_minimap)
assert(vim.b[source_buf].dotfiles_disable_hlchunk == original_hlchunk)

vim.api.nvim_set_current_win(source_win)
vim.api.nvim_win_set_buf(source_win, source_buf)
local failure_view = vim.api.nvim_win_call(source_win, vim.fn.winsaveview)
local failure_alternate = alternate_buffer(source_win)
local snacks = require("snacks")
local original_layout_new = snacks.layout.new
local failed_scratch
snacks.layout.new = function(opts)
	local layout = original_layout_new(opts)
	layout.show = function()
		failed_scratch = vim.api.nvim_win_get_buf(source_win)
		error("intentional layout failure")
	end
	return layout
end
peek.toggle()
snacks.layout.new = original_layout_new
assert(failed_scratch and failed_scratch ~= source_buf, "layout failure must occur after underlay detachment")
assert(
	vim.wait(1000, function()
		return vim.api.nvim_win_get_buf(source_win) == source_buf
			and vim.w[source_win].dotfiles_git_diff_peek_underlay == original_underlay_flag
	end, 20),
	"layout failure did not restore the source underlay"
)
assert(not vim.api.nvim_buf_is_valid(failed_scratch), "layout failure did not wipe the underlay scratch")
assert(vim.deep_equal(vim.api.nvim_win_call(source_win, vim.fn.winsaveview), failure_view))
assert(alternate_buffer(source_win) == failure_alternate, "layout failure changed the alternate buffer")
assert(vim.w[source_win].dotfiles_disable_minimap == original_disable_minimap)
assert(vim.b[source_buf].dotfiles_disable_hlchunk == original_hlchunk)
assert(
	vim.iter(vim.api.nvim_tabpage_list_wins(0)):all(function(win)
		return not vim.startswith(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)), "gitsigns://")
	end),
	"layout failure left a Gitsigns revision window behind"
)

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

print("Git diff peek popup regression: ok")
