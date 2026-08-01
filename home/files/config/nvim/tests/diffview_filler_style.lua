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
local git_diff_peek = require("config.git_diff_peek")
local expected_git_diff_peek = vim.fs.joinpath(nvim_root, "lua/config/git_diff_peek.lua")
local loaded_git_diff_peek = assert(debug.getinfo(git_diff_peek.apply_editor_chrome, "S").source):gsub("^@", "")
assert(vim.uv.fs_realpath(loaded_git_diff_peek) == vim.uv.fs_realpath(expected_git_diff_peek))

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
local schedule_diffview_cursorline_styles = upvalue(style_diff_window, "schedule_diffview_cursorline_styles")
local refresh_diffview_cursorline_styles =
	upvalue(schedule_diffview_cursorline_styles, "refresh_diffview_cursorline_styles")
local apply_diffview_cursorline_style = upvalue(refresh_diffview_cursorline_styles, "apply_diffview_cursorline_style")

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
vim.go.statuscolumn = "%=%l"
local scenes = {
	{ name = "default", suffix = "Default", bg = "#223344", fg = "#ff7700" },
	{ name = "insert", suffix = "Insert", bg = "#224433", fg = "#44ffaa" },
	{ name = "visual", suffix = "Visual", bg = "#334466", fg = "#77aaff" },
	{ name = "replace", suffix = "Replace", bg = "#553322", fg = "#ffaa44" },
	{ name = "command", suffix = "Command", bg = "#442244", fg = "#ff44aa" },
}
for _, scene in ipairs(scenes) do
	local suffix = scene.suffix
	for _, base in ipairs({
		"CursorLine",
		"CursorLineSign",
		"CursorLineFold",
		"CursorLineFoldOpen",
		"CursorLineFoldClosed",
		"CursorLineFoldDepth",
		"CursorLineNr",
		"CursorLineCodexNr",
	}) do
		vim.api.nvim_set_hl(0, "Dotfiles" .. base .. suffix, {
			fg = base:find("Nr", 1, true) and scene.fg or nil,
			bg = scene.bg,
			bold = base:find("Nr", 1, true) ~= nil,
			force = true,
		})
	end
	vim.api.nvim_set_hl(0, "DotfilesStatuscolumnMarker" .. suffix, {
		fg = scene.fg,
		bold = true,
		force = true,
	})
	for _, base in ipairs({
		"DiffCursorLineSign",
		"DiffCursorLineFold",
		"DiffCursorLineFoldOpen",
		"DiffCursorLineFoldClosed",
		"DiffCursorLineFoldDepth",
		"DiffCursorLineNr",
		"DiffCursorLineCodexNr",
	}) do
		vim.api.nvim_set_hl(0, "Dotfiles" .. base .. suffix, {
			fg = base:find("Nr", 1, true) and scene.fg or "#00aaff",
			bold = base:find("Nr", 1, true) ~= nil,
			force = true,
		})
	end
end
vim.wo.winhighlight = "DiffChange:DiffviewDiffChange,DiffText:DiffviewDiffText"
local win = vim.api.nvim_get_current_win()
local original_foldlevelstart = vim.o.foldlevelstart
diffview.opts.hooks.diff_buf_win_enter(0, win, { layout_name = "diff2_horizontal", symbol = "a" })
assert(vim.o.foldlevelstart == original_foldlevelstart, "Diffview styling must not change global foldlevelstart")
assert(vim.wo.foldcolumn == "1", "Diffview editor chrome must use one fold column")
assert(vim.wo.foldlevel == 0 and vim.wo.foldenable, "Diffview editor chrome fold state mismatch")
assert(vim.wo.signcolumn == "no", "Diffview editor chrome must disable native signcolumn")
assert(vim.wo.statuscolumn ~= "", "Diffview editor chrome must use the custom statuscolumn")
assert(vim.wo.number and vim.wo.relativenumber and vim.wo.numberwidth == 3, "Diffview number chrome mismatch")
assert(
	vim.wo.winbar == "" or vim.wo.winbar:find("dropbar", 1, true),
	"Diffview winbar must use Dropbar when configured"
)
assert(vim.wo.fillchars:find("diff: ", 1, true), "Diffview addition filler must render as a blank space")
assert(vim.w[win].dotfiles_disable_minimap == true, "the left Diffview pane must not receive a minimap")
assert(type(diffview_windows[win]) == "table", "Diffview editor windows must receive adaptive cursor-line state")
assert(diffview_windows[win].hl_ns == nil, "Diffview must not install a redraw-time highlight namespace")
assert(vim.b[vim.api.nvim_win_get_buf(win)].dotfiles_disable_hlchunk, "Diffview editors must suppress chunk borders")
assert(vim.wo.cursorline, "Diffview code windows must enable the ordinary cursor line")
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

local function target_for(source)
	return vim.wo[win].winhighlight:match(source .. ":([^,]+)")
end

for _, scene in ipairs(scenes) do
	apply_diffview_cursorline_style(win, scene.name, false)
	assert(vim.wo[win].cursorlineopt == "both", scene.name .. " unchanged rows must paint the full cursor line")
	assert(
		target_for("CursorLine") == "DotfilesCursorLine" .. scene.suffix,
		scene.name .. " unchanged row lost its mode-aware body"
	)
	local ordinary_number = vim.api.nvim_get_hl(0, { name = target_for("CursorLineNr"), link = false })
	assert(ordinary_number.bg == tonumber(scene.bg:sub(2), 16), scene.name .. " unchanged number lost its background")

	apply_diffview_cursorline_style(win, scene.name, true)
	assert(vim.wo[win].cursorlineopt == "number", scene.name .. " changed rows must suppress body CursorLine")
	assert(
		target_for("CursorLine") == "DotfilesCursorLine" .. scene.suffix,
		scene.name .. " changed row must retain the ordinary body target for the next unchanged row"
	)
	assert(
		target_for("CursorLineNr") == "DotfilesDiffCursorLineNr" .. scene.suffix,
		scene.name .. " changed row lost its mode-aware number foreground"
	)
	for _, source in ipairs({
		"CursorLineNr",
		"CursorLineSign",
		"CursorLineFold",
		"DotfilesCursorLineFoldOpen",
		"DotfilesCursorLineFoldClosed",
		"DotfilesCursorLineFoldDepth",
		"DotfilesCursorLineCodexNr",
	}) do
		local attributes = vim.api.nvim_get_hl(0, { name = assert(target_for(source)), link = false })
		assert(
			attributes.bg == nil,
			scene.name .. " changed-row rail leaked a CursorLine background through " .. source
		)
	end
	local diff_number = vim.api.nvim_get_hl(0, { name = target_for("CursorLineNr"), link = false })
	assert(diff_number.fg == tonumber(scene.fg:sub(2), 16), scene.name .. " changed number lost its mode color")
	assert(diff_number.bold, scene.name .. " changed number must remain bold")
	local marker = vim.api.nvim_get_hl(0, { name = target_for("DotfilesStatuscolumnMarker"), link = false })
	assert(marker.bg == nil, scene.name .. " neighboring relative-number marker retained a background")
end

apply_diffview_cursorline_style(win, "default", false)
local stable_winhighlight = vim.wo[win].winhighlight
for _ = 1, 1000 do
	apply_diffview_cursorline_style(win, "default", false)
end
assert(vim.wo[win].winhighlight == stable_winhighlight, "stable cursor movement must not rewrite winhighlight")
apply_diffview_cursorline_style(win, "default", true)
vim.wo[win].winhighlight = vim.wo[win].winhighlight:gsub(
	"CursorLineNr:DotfilesDiffCursorLineNrDefault",
	"CursorLineNr:DotfilesCursorLineNrDefault"
)
apply_diffview_cursorline_style(win, "default", true)
assert(
	target_for("CursorLineNr") == "DotfilesDiffCursorLineNrDefault",
	"an external mode-UI refresh must not leave a changed row with the ordinary number background"
)
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
		return vim.wo[gitsigns_main].cursorlineopt == "both"
			and vim.wo[gitsigns_main].winhighlight:find("DiffChange:DiffviewDiffChangeAdd", 1, true) ~= nil
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
	assert(
		vim.wo[win].cursorlineopt == "both",
		side .. " Gitsigns pane must use the ordinary full cursor line on unchanged rows"
	)
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

vim.api.nvim_win_set_cursor(gitsigns_main, { 3, 0 })
vim.cmd.diffupdate()
refresh_diffview_cursorline_styles()
assert(
	vim.api.nvim_win_call(gitsigns_main, function()
		return vim.fn.diff_hlID(3, 1) ~= 0
	end),
	"the fixture's added row must expose a native diff highlight"
)
assert(vim.wo[gitsigns_main].cursorlineopt == "number", "an added row must suppress the body CursorLine")
assert(
	vim.wo[gitsigns_main].winhighlight:find("CursorLineNr:DotfilesDiffCursorLineNrDefault", 1, true),
	"an added row must use the background-free mode-aware line number"
)
vim.api.nvim_win_set_cursor(gitsigns_main, { 6, 0 })
refresh_diffview_cursorline_styles()
assert(vim.wo[gitsigns_main].cursorlineopt == "both", "leaving a hunk must restore the full CursorLine")
assert(
	vim.wo[gitsigns_main].winhighlight:find("CursorLineNr:DotfilesCursorLineNrDefault", 1, true),
	"leaving a hunk must restore the ordinary mode-aware line number"
)
assert(vim.bo[gitsigns_revision_buf].modifiable and not vim.bo[gitsigns_revision_buf].readonly)
assert(vim.bo[gitsigns_main_buf].modifiable and not vim.bo[gitsigns_main_buf].readonly)
assert(
	vim.wo[gitsigns_revision].winhighlight:find("DiffAdd:DiffviewDiffAddAsDelete", 1, true),
	"Gitsigns revision additions must render as Diffview deletions"
)
assert(
	vim.wo[gitsigns_revision].winhighlight:find("DiffDelete:DiffviewDiffDeleteDim", 1, true),
	"Gitsigns revision filler must match Diffview's uncolored alignment filler"
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
			and vim.wo[gitsigns_main].winhighlight == original_main_winhighlight
	end),
	"closing a Gitsigns diff did not restore the editor window style"
)
assert(
	vim.wo[gitsigns_main].winhighlight == original_main_winhighlight,
	"Gitsigns diff left stale winhighlight mappings"
)
assert(not vim.b[gitsigns_main_buf].dotfiles_disable_hlchunk, "Gitsigns diff left hlchunk disabled")

print("Diffview blank filler regression: ok")
