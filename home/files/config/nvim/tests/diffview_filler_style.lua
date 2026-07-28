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
	"DiffviewDiffChangeDelete",
	"DiffviewDiffTextDelete",
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

print("Diffview blank filler regression: ok")
