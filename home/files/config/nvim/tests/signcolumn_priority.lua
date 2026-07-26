local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
vim.opt.runtimepath:prepend(nvim_root)
vim.opt.runtimepath:append(vim.fn.stdpath("data") .. "/lazy/statuscol.nvim")
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")

local specs = dofile(vim.fs.joinpath(nvim_root, "lua/plugins/git.lua"))
local priority = assert(specs[1].opts.sign_priority, "Gitsigns priority must be configured")
assert(priority > 30, "Gitsigns must outrank Codex and diagnostic signs")

vim.api.nvim_buf_set_lines(0, 0, -1, false, { "sign priority regression" })
vim.bo.modified = false
vim.wo.cursorline = true
vim.wo.cursorlineopt = "both"
vim.api.nvim_set_hl(0, "GitSignsAdd", { fg = "#00ff00" })
vim.api.nvim_set_hl(0, "GitSignsChange", { fg = "#ffff00" })
vim.api.nvim_set_hl(0, "DiagnosticSignError", { fg = "#ff0000" })
vim.api.nvim_set_hl(0, "DiagnosticInfo", { fg = "#00ffff" })
require("config.statuscolumn").setup()

local git_namespace = vim.api.nvim_create_namespace("gitsigns_signs_test")
local staged_git_namespace = vim.api.nvim_create_namespace("gitsigns_signs_test_staged")
local review_namespace = vim.api.nvim_create_namespace("dotfiles-review-added-file")
local diagnostic_namespace = vim.api.nvim_create_namespace("dotfiles-test-diagnostics")
local codex_namespace = vim.api.nvim_create_namespace("dotfiles-codex-edit-signs")
local legacy_group = "dotfiles-statuscolumn-legacy-test"
local legacy_name = "DotfilesLegacyStatuscolumnTest"
local bufnr = vim.api.nvim_get_current_buf()

local function rendered_statuscolumn_result(lnum)
	vim.cmd.redrawstatus()
	return vim.api.nvim_eval_statusline(vim.wo.statuscolumn, {
		maxwidth = 20,
		use_statuscol_lnum = lnum or 1,
		winid = vim.api.nvim_get_current_win(),
		highlights = true,
	})
end

local function rendered_statuscolumn()
	return rendered_statuscolumn_result().str
end

local function assert_isolated_signs(result, expected, base)
	local count = 0
	for index, highlight in ipairs(result.highlights) do
		if highlight.group:match("^DotfilesStatuscolumnSign%d+$") then
			count = count + 1
			assert(result.highlights[index - 1].group == base, "each sign cell must start from the native sign base")
			assert(
				vim.api.nvim_get_hl(0, { name = highlight.group, link = false }).nocombine == true,
				"each sign cell must reject inherited number styles"
			)
		end
	end
	assert(count == expected, ("expected %d isolated sign cells, got %d"):format(expected, count))
end

vim.api.nvim_buf_set_extmark(0, git_namespace, 0, 0, {
	priority = priority,
	sign_text = "G",
	sign_hl_group = "GitSignsAdd",
})
local git_only = rendered_statuscolumn()
assert(git_only:match("1G$") ~= nil, "Git must render immediately after the line number: " .. git_only)

local git_highlights = rendered_statuscolumn_result().highlights
local git_highlight_index
for index, highlight in ipairs(git_highlights) do
	if highlight.group:match("^DotfilesStatuscolumnSign%d+$") then
		git_highlight_index = index
		break
	end
end
assert(git_highlight_index ~= nil, "Git sign highlight must be present")
assert(
	git_highlights[git_highlight_index - 1].group == "CursorLineSign",
	"Git signs must reset the line-number style to the native sign-column base"
)
local isolated_git_highlight = vim.api.nvim_get_hl(0, {
	name = git_highlights[git_highlight_index].group,
	link = false,
})
assert(isolated_git_highlight.nocombine == true, "Git sign style must not inherit bold from the line number")
assert(
	isolated_git_highlight.fg == vim.api.nvim_get_hl(0, { name = "GitSignsAdd", link = false }).fg,
	"isolated Git sign highlight must preserve its source foreground"
)

vim.api.nvim_set_hl(0, "GitSignsAdd", { fg = "#ff00ff" })
vim.api.nvim_exec_autocmds("ColorScheme", { modeline = false })
local refreshed_highlights = rendered_statuscolumn_result().highlights
for _, highlight in ipairs(refreshed_highlights) do
	if highlight.group:match("^DotfilesStatuscolumnSign%d+$") then
		assert(
			vim.api.nvim_get_hl(0, { name = highlight.group, link = false }).fg == 0xff00ff,
			"isolated sign highlights must refresh after a colorscheme change"
		)
		break
	end
end

vim.api.nvim_buf_set_extmark(0, staged_git_namespace, 0, 0, {
	priority = priority,
	sign_text = "S",
	sign_hl_group = "GitSignsChange",
})
assert(
	rendered_statuscolumn():match("1GS$") ~= nil,
	"Git segment must keep two staged and unstaged signs: " .. rendered_statuscolumn()
)
assert_isolated_signs(rendered_statuscolumn_result(), 2, "CursorLineSign")

vim.fn.sign_define(legacy_name, { text = "L", texthl = "DiagnosticInfo" })
vim.fn.sign_place(1, legacy_group, legacy_name, bufnr, { lnum = 1, priority = 40 })
local with_legacy = rendered_statuscolumn()
assert(with_legacy:match("1GSL$") ~= nil, "legacy signs must render in the auxiliary segment")
vim.fn.sign_unplace(legacy_group, { buffer = bufnr, id = 1 })

vim.api.nvim_buf_set_extmark(0, diagnostic_namespace, 0, 0, {
	priority = 10,
	sign_text = "D",
	sign_hl_group = "DiagnosticSignError",
})
local with_diagnostic = rendered_statuscolumn()
assert(with_diagnostic:match("1GSD$") ~= nil, "diagnostic must use the auxiliary segment")
assert_isolated_signs(rendered_statuscolumn_result(), 3, "CursorLineSign")

vim.api.nvim_buf_set_extmark(0, codex_namespace, 0, 0, {
	priority = 30,
	sign_text = "C",
	sign_hl_group = "DiagnosticInfo",
})
assert(
	rendered_statuscolumn():match("1GSCD$") ~= nil,
	"Codex must precede diagnostics in the two-cell auxiliary segment"
)

vim.api.nvim_buf_clear_namespace(0, diagnostic_namespace, 0, -1)
vim.api.nvim_buf_clear_namespace(0, codex_namespace, 0, -1)
vim.api.nvim_buf_clear_namespace(0, staged_git_namespace, 0, -1)
vim.api.nvim_buf_set_extmark(0, review_namespace, 0, 0, {
	priority = 20,
	sign_text = "R",
})
assert(rendered_statuscolumn():match("1GR$") ~= nil, "review-added signs must share the Git segment with Gitsigns")

vim.api.nvim_buf_clear_namespace(0, review_namespace, 0, -1)
vim.api.nvim_buf_clear_namespace(0, git_namespace, 0, -1)
assert(rendered_statuscolumn():match("1$") ~= nil, "empty sign segments must collapse automatically")

vim.api.nvim_buf_set_lines(0, 0, -1, false, { "above", "cursor", "below" })
vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.api.nvim_buf_set_extmark(0, git_namespace, 0, 0, {
	priority = priority,
	sign_text = "G",
	sign_hl_group = "GitSignsAdd",
})
local marker_highlights = rendered_statuscolumn_result(1).highlights
local marker_sign_index
for index, highlight in ipairs(marker_highlights) do
	if highlight.group:match("^DotfilesStatuscolumnSign%d+$") then
		marker_sign_index = index
		break
	end
end
assert(marker_sign_index ~= nil, "marker-line Git sign highlight must be present")
assert(
	marker_highlights[marker_sign_index - 1].group == "SignColumn",
	"non-current signs must reset the bold marker style to SignColumn"
)

print("statuscolumn sign routing regression: ok")
