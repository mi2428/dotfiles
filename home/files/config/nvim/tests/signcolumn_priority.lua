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

vim.api.nvim_buf_set_lines(0, 0, -1, false, { "sign priority regression", "fold body" })
vim.bo.modified = false
vim.wo.number = true
vim.wo.relativenumber = true
vim.wo.cursorline = true
vim.wo.cursorlineopt = "both"
vim.wo.foldcolumn = "1"
vim.wo.foldmethod = "manual"
vim.opt.fillchars:append({ fold = " ", foldopen = "", foldclose = "", foldsep = " " })
vim.api.nvim_set_hl(0, "GitSignsAdd", { fg = "#00ff00" })
vim.api.nvim_set_hl(0, "GitSignsChange", { fg = "#ffff00" })
vim.api.nvim_set_hl(0, "DiagnosticSignError", { fg = "#ff0000" })
vim.api.nvim_set_hl(0, "DiagnosticSignWarn", { fg = "#ffff00" })
vim.api.nvim_set_hl(0, "DiagnosticInfo", { fg = "#00ffff" })
vim.api.nvim_set_hl(0, "DotfilesStatuscolumnMarker", { fg = "#ffffff", bold = true })
vim.api.nvim_set_hl(0, "DotfilesCodexLineNr", { fg = "#00ffff", bold = true })
vim.api.nvim_set_hl(0, "DotfilesCursorLineCodexNr", { fg = "#00ffff", bold = true })
require("config.statuscolumn").setup()
vim.cmd("1,2fold")
vim.cmd.normal({ args = { "zO" }, bang = true })

local git_namespace = vim.api.nvim_create_namespace("gitsigns_signs_test")
local staged_git_namespace = vim.api.nvim_create_namespace("gitsigns_signs_test_staged")
local review_namespace = vim.api.nvim_create_namespace("dotfiles-review-added-file")
local diagnostic_namespace = vim.api.nvim_create_namespace("nvim.dotfiles-test.diagnostic.signs")
local codex_namespace = vim.api.nvim_create_namespace("dotfiles-codex-edit-signs")
local legacy_group = "dotfiles-statuscolumn-legacy-test"
local legacy_name = "DotfilesLegacyStatuscolumnTest"
local bufnr = vim.api.nvim_get_current_buf()

local function rendered_statuscolumn_result(lnum, maxwidth)
	vim.cmd.redrawstatus()
	return vim.api.nvim_eval_statusline(vim.wo.statuscolumn, {
		maxwidth = maxwidth or 20,
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
local two_git = rendered_statuscolumn()
assert(two_git:match("1[GS]$") ~= nil, "the Git colorbar must render exactly one sign: " .. two_git)
assert(two_git:match("GS$") == nil, "staged and unstaged Git signs must share one colorbar cell: " .. two_git)
assert_isolated_signs(rendered_statuscolumn_result(), 1, "CursorLineSign")

vim.fn.sign_define(legacy_name, { text = "L", texthl = "DiagnosticInfo" })
vim.fn.sign_place(1, legacy_group, legacy_name, bufnr, { lnum = 1, priority = 40 })
local with_legacy = rendered_statuscolumn()
assert(with_legacy == two_git, "unrouted legacy signs must not appear beside the Git-only colorbar")
vim.fn.sign_unplace(legacy_group, { buffer = bufnr, id = 1 })

vim.api.nvim_buf_set_extmark(0, diagnostic_namespace, 0, 0, {
	priority = 10,
	sign_text = "●",
	sign_hl_group = "DiagnosticSignError",
})
local with_diagnostic = rendered_statuscolumn()
assert(
	with_diagnostic:match("1[GS]● $") ~= nil,
	"diagnostic must render after the line number and Git colorbar: " .. with_diagnostic
)
local right_columns = assert(with_diagnostic:match("1([GS]● )$"), "the three right-hand cells must be present")
assert(vim.fn.strdisplaywidth(right_columns) == 3, "Git and diagnostic signs must use at most three cells")
local compact_diagnostic = rendered_statuscolumn_result(1, 7)
local diagnostic_start
local diagnostic_end
for index, highlight in ipairs(compact_diagnostic.highlights) do
	if
		highlight.group:match("^DotfilesStatuscolumnSign%d+$")
		and vim.api.nvim_get_hl(0, { name = highlight.group, link = false }).fg == 0xff0000
	then
		diagnostic_start = highlight.start
		for next_index = index + 1, #compact_diagnostic.highlights do
			if compact_diagnostic.highlights[next_index].start > diagnostic_start then
				diagnostic_end = compact_diagnostic.highlights[next_index].start
				break
			end
		end
		break
	end
end
assert(diagnostic_start ~= nil and diagnostic_end ~= nil, "diagnostic highlight boundaries must be present")
local diagnostic_cell = compact_diagnostic.str:sub(diagnostic_start + 1, diagnostic_end)
assert(vim.fn.strdisplaywidth(diagnostic_cell) == 2, "diagnostics must retain their padding cell: " .. vim.inspect({
	cell = diagnostic_cell,
	result = compact_diagnostic,
}))
assert_isolated_signs(rendered_statuscolumn_result(), 2, "CursorLineSign")

vim.api.nvim_buf_set_extmark(0, codex_namespace, 0, 0, {
	priority = 30,
	sign_text = "",
	sign_hl_group = "DiagnosticInfo",
})
local with_codex = rendered_statuscolumn_result()
assert(with_codex.str == with_diagnostic, "Codex must color the number without adding a sign cell")
assert(
	with_codex.str:match("^%s+1[GS]● $") ~= nil,
	"the combined row must render fold, number, Git, and diagnostic in the requested order: " .. with_codex.str
)
assert(
	vim.iter(with_codex.highlights):any(function(highlight)
		return highlight.group == "DotfilesCursorLineCodexNr"
	end),
	"the latest Codex edit must use the dedicated current-line number highlight: " .. vim.inspect(with_codex.highlights)
)
vim.api.nvim_win_set_cursor(0, { 2, 0 })
local noncurrent_codex = rendered_statuscolumn_result(1)
assert(
	vim.iter(noncurrent_codex.highlights):any(function(highlight)
		return highlight.group == "DotfilesCodexLineNr"
	end),
	"moving the cursor away must preserve the Codex color on the edited line number"
)
vim.api.nvim_win_set_cursor(0, { 1, 0 })

vim.api.nvim_buf_clear_namespace(0, diagnostic_namespace, 0, -1)
vim.api.nvim_buf_clear_namespace(0, codex_namespace, 0, -1)
vim.api.nvim_buf_clear_namespace(0, staged_git_namespace, 0, -1)
vim.api.nvim_buf_clear_namespace(0, git_namespace, 0, -1)
vim.api.nvim_buf_set_extmark(0, review_namespace, 0, 0, {
	priority = 20,
	sign_text = "▎",
})
assert(rendered_statuscolumn():match("1▎$") ~= nil, "review-added signs must share the Git colorbar cell")

vim.api.nvim_buf_clear_namespace(0, review_namespace, 0, -1)
assert(rendered_statuscolumn():match("1$") ~= nil, "empty sign segments must collapse automatically")

vim.cmd.normal({ args = { "zE" }, bang = true })
vim.wo.foldcolumn = "0"
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "above", "cursor", "below" })
vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.api.nvim_buf_set_extmark(0, git_namespace, 0, 0, {
	priority = priority,
	sign_text = "G",
	sign_hl_group = "GitSignsAdd",
})
local marker_result = rendered_statuscolumn_result(1)
assert(
	marker_result.str:match("󰄿G$") ~= nil,
	"the upper marker must render before the Git sign: " .. marker_result.str
)
assert(
	vim.iter(marker_result.highlights):any(function(highlight)
		return highlight.group == "DotfilesStatuscolumnMarker"
	end),
	"the upper marker must use its dedicated highlight: " .. vim.inspect(marker_result.highlights)
)
local marker_highlights = marker_result.highlights
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
