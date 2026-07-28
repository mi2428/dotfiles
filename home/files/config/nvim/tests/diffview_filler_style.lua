local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
vim.opt.runtimepath:prepend(nvim_root)
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")

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

local specs = dofile(vim.fs.joinpath(nvim_root, "lua/plugins/git.lua"))
local diffview = specs[2]
local set_diffview_highlights = upvalue(diffview.init, "set_diffview_highlights")
local style_diff_window = upvalue(diffview.opts.hooks.diff_buf_win_enter, "style_diff_window")
local diffview_windows = upvalue(style_diff_window, "diffview_windows")
local refresh_diffview_cursorline_namespaces = upvalue(style_diff_window, "refresh_diffview_cursorline_namespaces")

vim.api.nvim_set_hl(0, "DiffDelete", { fg = "#ff0000", bg = "#440000" })
set_diffview_highlights()
local filler = vim.api.nvim_get_hl(0, { name = "DiffviewDiffDeleteDim", link = false })
local deletion = vim.api.nvim_get_hl(0, { name = "DiffDelete", link = false })
assert(filler.fg == nil and filler.bg == nil, "Diffview alignment filler must be completely uncolored")
assert(deletion.fg ~= nil and deletion.bg ~= nil, "real deletion highlighting must remain intact")

for _, name in ipairs({
	"DiffviewDiffAddAsDelete",
	"DiffviewDiffChangeDelete",
	"DiffviewDiffTextDelete",
	"DiffviewDiffAdd",
	"DiffviewDiffChangeAdd",
	"DiffviewDiffTextAdd",
}) do
	local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
	assert(hl.bg ~= nil, name .. " must define a background")
end
assert(
	vim.api.nvim_get_hl(0, { name = "DiffviewDiffChangeDelete", link = false }).bg
		~= vim.api.nvim_get_hl(0, { name = "DiffviewDiffTextDelete", link = false }).bg,
	"deleted lines and changed text must use different intensities"
)
assert(
	vim.api.nvim_get_hl(0, { name = "DiffviewDiffChangeAdd", link = false }).bg
		~= vim.api.nvim_get_hl(0, { name = "DiffviewDiffTextAdd", link = false }).bg,
	"added lines and changed text must use different intensities"
)
assert(
	vim.api.nvim_get_hl(0, { name = "DiffviewDiffAddAsDelete", link = false }).bg
		== vim.api.nvim_get_hl(0, { name = "DiffviewDiffChangeDelete", link = false }).bg,
	"pure deletions and changed deletion lines must share the subtle red background"
)
assert(
	vim.api.nvim_get_hl(0, { name = "DiffviewDiffAdd", link = false }).bg
		== vim.api.nvim_get_hl(0, { name = "DiffviewDiffChangeAdd", link = false }).bg,
	"pure additions and changed addition lines must share the subtle green background"
)

local original_diffview = package.loaded.diffview
package.loaded.diffview = {
	setup = function()
		-- diffview.setup() creates this default link after the plugin's init hook.
		vim.api.nvim_set_hl(0, "DiffviewDiffDeleteDim", { link = "Comment" })
	end,
}
diffview.config(nil, diffview.opts)
package.loaded.diffview = original_diffview
filler = vim.api.nvim_get_hl(0, { name = "DiffviewDiffDeleteDim", link = false })
assert(filler.fg == nil and filler.bg == nil, "Diffview setup restored colored alignment filler")

vim.wo.fillchars = "diff:-"
vim.wo.cursorline = false
local cursorline_test_groups = {
	CursorLineNr = { target = "TestDiffCursorLineNr", attributes = { fg = "#ff8800", bg = "#112233", bold = true } },
	CursorLineSign = { target = "TestDiffCursorLineSign", attributes = { bg = "#112233" } },
	CursorLineFold = { target = "TestDiffCursorLineFold", attributes = { fg = "#00aaff", bg = "#112233" } },
	DotfilesCursorLineFoldOpen = {
		target = "TestDiffCursorLineFoldOpen",
		attributes = { fg = "#00ffaa", bg = "#112233" },
	},
	DotfilesCursorLineFoldClosed = {
		target = "TestDiffCursorLineFoldClosed",
		attributes = { fg = "#aa00ff", bg = "#112233" },
	},
	DotfilesCursorLineFoldDepth = {
		target = "TestDiffCursorLineFoldDepth",
		attributes = { fg = "#777777", bg = "#112233" },
	},
	DotfilesStatuscolumnMarker = {
		target = "TestDiffStatuscolumnMarker",
		attributes = { fg = "#ff8800", bg = "#112233", bold = true },
	},
	DotfilesCursorLineCodexNr = {
		target = "TestDiffCursorLineCodexNr",
		attributes = { fg = "#00ffff", bg = "#112233", bold = true },
	},
}
local winhighlight = {
	"DiffChange:DiffviewDiffChange",
	"DiffText:DiffviewDiffText",
}
vim.api.nvim_set_hl(0, "CursorLine", { bg = "#112233" })
for source, spec in pairs(cursorline_test_groups) do
	vim.api.nvim_set_hl(0, source, spec.attributes)
	vim.api.nvim_set_hl(0, spec.target, spec.attributes)
	winhighlight[#winhighlight + 1] = source .. ":" .. spec.target
end
vim.wo.winhighlight = table.concat(winhighlight, ",")
local win = vim.api.nvim_get_current_win()
diffview.opts.hooks.diff_buf_win_enter(0, win, { layout_name = "diff2_horizontal", symbol = "a" })
assert(vim.wo.fillchars:find("diff: ", 1, true), "Diffview addition filler must render as a blank space")
assert(vim.w[win].dotfiles_disable_minimap == true, "the left Diffview pane must not receive a minimap")
assert(type(diffview_windows[win]) == "table", "Diffview editor windows must receive cursor-line redraw state")
assert(
	vim.wait(1000, function()
		return diffview_windows[win].hl_ns ~= nil
	end),
	"Diffview editor windows must receive a cursor-line highlight namespace"
)
local cursorline_target = vim.wo.winhighlight:match("CursorLine:([^,]+)") or "CursorLine"
local cursorline = vim.api.nvim_get_hl(0, { name = cursorline_target, link = false })
local diff_change_on_cursor = vim.api.nvim_get_hl(diffview_windows[win].hl_ns, {
	name = "DiffviewDiffChangeDelete",
	link = false,
})
assert(
	diff_change_on_cursor.bg == cursorline.bg,
	"the redraw namespace must replace diff backgrounds with the ordinary CursorLine background"
)
for source, spec in pairs(cursorline_test_groups) do
	local expected = vim.api.nvim_get_hl(0, { name = spec.target, link = false })
	local source_hl = vim.api.nvim_get_hl(diffview_windows[win].hl_ns, { name = source, link = false })
	local target_hl = vim.api.nvim_get_hl(diffview_windows[win].hl_ns, { name = spec.target, link = false })
	assert(
		source_hl.bg == cursorline.bg,
		("%s must follow the Diffview cursor-row background (expected %s, got %s)"):format(
			source,
			vim.inspect(cursorline.bg),
			vim.inspect(source_hl.bg)
		)
	)
	assert(
		target_hl.bg == cursorline.bg,
		("%s must follow the Diffview cursor-row background (expected %s, got %s)"):format(
			spec.target,
			vim.inspect(cursorline.bg),
			vim.inspect(target_hl.bg)
		)
	)
	assert(source_hl.fg == expected.fg, source .. " must preserve its mode-specific foreground")
	assert(target_hl.fg == expected.fg, spec.target .. " must preserve its mode-specific foreground")
end
assert(vim.b[vim.api.nvim_win_get_buf(win)].dotfiles_disable_hlchunk, "Diffview editors must suppress chunk borders")
assert(vim.wo.cursorline, "Diffview code windows must enable the ordinary cursor line")
assert(
	vim.wo.cursorlineopt == "number",
	"Diffview must leave editor-row painting to its redraw namespace without a second line decoration"
)
assert(
	vim.wo.winhighlight:find("CursorLine:CursorLine", 1, true),
	"Diffview must not replace the mode-aware cursor line with a static highlight"
)
assert(
	vim.wo.winhighlight:find("DiffChange:DiffviewDiffChangeDelete", 1, true),
	"left changed lines must use the deletion background"
)
assert(
	vim.wo.winhighlight:find("DiffText:DiffviewDiffTextDelete", 1, true),
	"left inline changes must use the strong deletion background"
)

diffview.opts.hooks.diff_buf_win_enter(0, win, { layout_name = "diff2_vertical", symbol = "b" })
assert(vim.w[win].dotfiles_disable_minimap == false, "the right Diffview pane must retain its minimap")
assert(
	vim.wo.winhighlight:find("DiffChange:DiffviewDiffChangeAdd", 1, true),
	"right changed lines must use the addition background"
)
assert(
	vim.wo.winhighlight:find("DiffText:DiffviewDiffTextAdd", 1, true),
	"right inline changes must use the strong addition background"
)

diffview.opts.hooks.diff_buf_win_enter(0, win, { layout_name = "diff3_horizontal", symbol = "a" })
assert(
	vim.wo.winhighlight:find("DiffChange:DiffviewDiffChange,", 1, true),
	"merge layouts must retain their neutral changed-line background"
)
assert(
	vim.wo.winhighlight:find("DiffText:DiffviewDiffText", 1, true),
	"merge layouts must retain their neutral inline-change background"
)

for _, scene in ipairs({
	{ name = "Normal", bg = "#223344", fg = "#ff7700" },
	{ name = "Command", bg = "#442244", fg = "#ff44aa" },
	{ name = "Insert", bg = "#224433", fg = "#44ffaa" },
}) do
	local mappings = {
		"DiffChange:DiffviewDiffChange",
		"DiffText:DiffviewDiffText",
	}
	local cursorline_scene_target = "TestDiffCursorLine" .. scene.name
	vim.api.nvim_set_hl(0, cursorline_scene_target, { bg = scene.bg })
	mappings[#mappings + 1] = "CursorLine:" .. cursorline_scene_target
	for source, spec in pairs(cursorline_test_groups) do
		local target = spec.target .. scene.name
		local attributes = vim.deepcopy(spec.attributes)
		attributes.bg = scene.bg
		if source == "CursorLineNr" or source == "DotfilesStatuscolumnMarker" then
			attributes.fg = scene.fg
		end
		vim.api.nvim_set_hl(0, target, attributes)
		mappings[#mappings + 1] = source .. ":" .. target
	end
	vim.wo.winhighlight = table.concat(mappings, ",")
	refresh_diffview_cursorline_namespaces()

	local scene_cursorline = vim.api.nvim_get_hl(0, { name = cursorline_scene_target, link = false })
	local cursor_number = vim.api.nvim_get_hl(diffview_windows[win].hl_ns, {
		name = "CursorLineNr",
		link = false,
	})
	local cursor_row_diff = vim.api.nvim_get_hl(diffview_windows[win].hl_ns, {
		name = "DiffviewDiffChangeDelete",
		link = false,
	})
	assert(cursor_number.bg == scene_cursorline.bg, scene.name .. " line number must match its editor row")
	assert(cursor_number.fg == tonumber(scene.fg:sub(2), 16), scene.name .. " line number must use its mode color")
	assert(cursor_row_diff.bg == scene_cursorline.bg, scene.name .. " diff row must use its mode color")
end
assert(diffview.opts.enhanced_diff_hl, "Diffview must separate deletion lines from alignment filler")

vim.cmd.tabnew()
local gitsigns_main = vim.api.nvim_get_current_win()
local gitsigns_main_buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_name(gitsigns_main_buf, "/tmp/dotfiles-gitsigns-diff-main.lua")
vim.api.nvim_buf_set_lines(gitsigns_main_buf, 0, -1, false, {
	"local value = 1",
	"",
	"local added_one = 1",
	"local added_two = 2",
	"local added_three = 3",
	"return value",
})
vim.bo[gitsigns_main_buf].filetype = "lua"
vim.wo[gitsigns_main].cursorline = true
vim.wo[gitsigns_main].cursorlineopt = "both"
vim.wo[gitsigns_main].fillchars = "diff:-"
vim.wo[gitsigns_main].winhighlight = "CursorLine:TestDiffCursorLineNormal"
local original_main_winhighlight = vim.wo[gitsigns_main].winhighlight

vim.cmd.vsplit()
local gitsigns_revision = vim.api.nvim_get_current_win()
local gitsigns_revision_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(gitsigns_revision_buf, "gitsigns:///tmp/.git//HEAD:dotfiles-gitsigns-diff-main.lua")
vim.api.nvim_win_set_buf(gitsigns_revision, gitsigns_revision_buf)
vim.api.nvim_buf_set_lines(gitsigns_revision_buf, 0, -1, false, { "local value = 1", "", "return value" })
vim.bo[gitsigns_revision_buf].filetype = "tf"
vim.bo[gitsigns_revision_buf].buftype = "nowrite"
vim.api.nvim_exec_autocmds("BufWinEnter", { buffer = gitsigns_revision_buf, modeline = false })
vim.api.nvim_exec_autocmds("FileType", { buffer = gitsigns_revision_buf, modeline = false })
vim.wo[gitsigns_main].diff = true
vim.wo[gitsigns_revision].diff = true
assert(
	vim.wait(1000, function()
		return vim.wo[gitsigns_main].cursorlineopt == "number"
	end),
	"Gitsigns diff windows did not receive the shared Diffview style"
)
assert(
	vim.wait(1000, function()
		return vim.treesitter.highlighter.active[gitsigns_revision_buf] ~= nil
	end),
	"Gitsigns revision buffers must start Tree-sitter despite their nowrite buftype"
)
assert(
	vim.bo[gitsigns_revision_buf].filetype == vim.bo[gitsigns_main_buf].filetype,
	"Gitsigns revision buffers must use the worktree filetype"
)

for win, side in pairs({
	[gitsigns_revision] = "Delete",
	[gitsigns_main] = "Add",
}) do
	assert(vim.wo[win].cursorline, side .. " Gitsigns pane must enable the Diffview cursor line")
	assert(vim.wo[win].cursorlineopt == "number", side .. " Gitsigns pane must suppress the editor-row underline")
	assert(vim.wo[win].fillchars:find("diff: ", 1, true), side .. " Gitsigns pane must use blank diff filler")
	assert(
		vim.b[vim.api.nvim_win_get_buf(win)].dotfiles_disable_hlchunk,
		side .. " Gitsigns pane must suppress chunk borders"
	)
	assert(
		vim.wo[win].winhighlight:find("DiffChange:DiffviewDiffChange" .. side, 1, true),
		side .. " Gitsigns pane must use the subtle changed-line background"
	)
	assert(
		vim.wo[win].winhighlight:find("DiffText:DiffviewDiffText" .. side, 1, true),
		side .. " Gitsigns pane must use the strong inline-change background"
	)
end
assert(
	vim.wo[gitsigns_revision].winhighlight:find("DiffAdd:DiffviewDiffAddAsDelete", 1, true),
	"Gitsigns revision additions must render as Diffview deletions"
)
assert(
	vim.wo[gitsigns_revision].winhighlight:find("DiffDelete:DiffviewDiffAddAsDelete", 1, true),
	"Gitsigns revision filler must render with the deletion background"
)
assert(
	vim.wo[gitsigns_main].winhighlight:find("DiffAdd:DiffviewDiffAdd", 1, true),
	"Gitsigns worktree additions must render as Diffview additions"
)
assert(
	vim.o.diffopt:find("filler", 1, true),
	"Gitsigns diff must retain Neovim filler rows for paired screen alignment"
)
assert(vim.wo[gitsigns_revision].foldenable, "Gitsigns revision pane must keep native diff folds enabled")
assert(vim.wo[gitsigns_main].foldenable, "Gitsigns worktree pane must keep native diff folds enabled")
for _, diff_win in ipairs({ gitsigns_revision, gitsigns_main }) do
	vim.api.nvim_win_call(diff_win, function()
		-- Keep folds enabled while exposing every buffer line for the focused
		-- filler assertion below. Disabling foldenable masks asymmetric diff-fold
		-- regressions in the real Gitsigns lifecycle.
		vim.cmd.normal({ args = { "zR" }, bang = true })
	end)
end
local function screen_row_for_buffer_line(win, lnum)
	return vim.api.nvim_win_call(win, function()
		local filler = 0
		for line = 1, lnum do
			filler = filler + vim.fn.diff_filler(line)
		end
		return lnum + filler
	end)
end
assert(
	screen_row_for_buffer_line(gitsigns_revision, 3) == screen_row_for_buffer_line(gitsigns_main, 6),
	"Gitsigns filler rows must keep the unchanged post-addition line screen-aligned"
)

vim.cmd.vsplit()
local diffview_coexist = vim.api.nvim_get_current_win()
local diffview_coexist_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(diffview_coexist_buf, "/tmp/dotfiles-diffview-coexist.lua")
vim.api.nvim_buf_set_lines(diffview_coexist_buf, 0, -1, false, { "local other = true" })
vim.api.nvim_win_set_buf(diffview_coexist, diffview_coexist_buf)
vim.wo[diffview_coexist].diff = true
vim.api.nvim_exec_autocmds("WinEnter", { modeline = false })
assert(
	vim.wait(1000, function()
		return vim.wo[diffview_coexist].winhighlight:find("DiffDelete:DiffviewDiffDeleteDim", 1, true) ~= nil
	end),
	"a coexisting non-Gitsigns diff pane must retain its blank Diffview filler"
)
assert(vim.w[gitsigns_revision].dotfiles_disable_minimap, "Gitsigns revision pane must hide the minimap")
assert(not vim.w[gitsigns_main].dotfiles_disable_minimap, "Gitsigns worktree pane must retain the minimap")

vim.wo[diffview_coexist].diff = false
vim.api.nvim_win_close(diffview_coexist, true)
vim.wo[gitsigns_main].diff = false
vim.api.nvim_win_close(gitsigns_revision, true)
vim.api.nvim_exec_autocmds("WinEnter", { modeline = false })
assert(
	vim.wait(1000, function()
		return vim.wo[gitsigns_main].cursorlineopt == "both"
	end),
	"closing a Gitsigns diff did not restore the editor window style"
)
assert(
	vim.wo[gitsigns_main].winhighlight == original_main_winhighlight,
	"Gitsigns diff left stale winhighlight mappings"
)
assert(not vim.b[gitsigns_main_buf].dotfiles_disable_hlchunk, "Gitsigns diff left hlchunk disabled")

print("Diffview blank filler regression: ok")
