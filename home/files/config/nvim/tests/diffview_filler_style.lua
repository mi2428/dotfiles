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
vim.wo.winhighlight = "DiffChange:DiffviewDiffChange,DiffText:DiffviewDiffText"
local win = vim.api.nvim_get_current_win()
diffview.opts.hooks.diff_buf_win_enter(0, win, { layout_name = "diff2_horizontal", symbol = "a" })
assert(vim.wo.fillchars:find("diff: ", 1, true), "Diffview addition filler must render as a blank space")
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
assert(diffview.opts.enhanced_diff_hl, "Diffview must separate deletion lines from alignment filler")

print("Diffview blank filler regression: ok")
