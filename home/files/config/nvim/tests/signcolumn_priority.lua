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
assert(vim.fn.strdisplaywidth("󰄽") == 1, "the left double-chevron error glyph must occupy one rail cell")
assert(vim.fn.strdisplaywidth("󰄾") == 1, "the double-chevron warning glyph must occupy one rail cell")
assert(vim.fn.strdisplaywidth("+") == 1, "the information glyph must occupy one rail cell")

vim.api.nvim_buf_set_lines(0, 0, -1, false, {
	"sign priority regression",
	"fold body one",
	"fold body two",
	"fold body three",
})
vim.bo.modified = false
vim.wo.number = true
vim.wo.relativenumber = true
vim.wo.cursorline = true
vim.wo.cursorlineopt = "both"
vim.wo.foldcolumn = "1"
vim.wo.foldmethod = "manual"
vim.opt.fillchars:append({ fold = " ", foldopen = "󰅀", foldclose = "󰅃", foldsep = " " })
vim.api.nvim_set_hl(0, "GitSignsAdd", { fg = "#00ff00" })
vim.api.nvim_set_hl(0, "GitSignsChange", { fg = "#ffff00" })
vim.api.nvim_set_hl(0, "DiagnosticSignError", { fg = "#ff0000", bg = "#110000" })
vim.api.nvim_set_hl(0, "DiagnosticSignWarn", { fg = "#ffff00", bg = "#111100" })
vim.api.nvim_set_hl(0, "DiagnosticSignInfo", { fg = "#00ffff", bg = "#001111" })
vim.api.nvim_set_hl(0, "DiagnosticInfo", { fg = "#00ffff" })
vim.api.nvim_set_hl(0, "FoldColumn", { fg = "#0000ff", bg = "#222222" })
vim.api.nvim_set_hl(0, "CursorLineFold", { fg = "#0000ff", bg = "#333333" })
vim.api.nvim_set_hl(0, "DotfilesTestCursorLineFold", { fg = "#0000ff", bg = "#444444" })
vim.wo.winhighlight = "CursorLineFold:DotfilesTestCursorLineFold"
vim.api.nvim_set_hl(0, "DotfilesStatuscolumnMarker", { fg = "#ffffff", bold = true })
vim.api.nvim_set_hl(0, "DotfilesCursorLineFoldOpen", { fg = "#0000ff" })
vim.api.nvim_set_hl(0, "DotfilesCursorLineFoldClosed", { fg = "#ff00ff" })
vim.api.nvim_set_hl(0, "DotfilesCodexLineNr", { fg = "#00ffff", bold = true })
vim.api.nvim_set_hl(0, "DotfilesCursorLineCodexNr", { fg = "#00ffff", bold = true })
require("config.statuscolumn").setup()
vim.cmd("1,4fold")
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

assert(
	rendered_statuscolumn_result(2).str:sub(1, 1) == "1",
	"the first open-fold continuation must start with its depth label"
)
local depth_diagnostic = vim.api.nvim_buf_set_extmark(0, diagnostic_namespace, 1, 0, {
	priority = 10,
	sign_text = "●",
	sign_hl_group = "DiagnosticSignWarn",
})
assert(
	rendered_statuscolumn_result(2).str:sub(1, #"●") == "●",
	"a diagnostic must replace a fold depth label in the rail"
)
vim.api.nvim_buf_del_extmark(0, diagnostic_namespace, depth_diagnostic)
assert(rendered_statuscolumn_result(2).str:sub(1, 1) == "1", "removing a diagnostic must restore the fold depth label")

vim.api.nvim_buf_set_extmark(0, diagnostic_namespace, 0, 0, {
	priority = 10,
	sign_text = "●",
	sign_hl_group = "DiagnosticSignError",
})
local with_diagnostic = rendered_statuscolumn()
assert(
	with_diagnostic:match("^●%s+1[GS]$") ~= nil,
	"diagnostic must replace the open-fold glyph while Git stays after the number: " .. with_diagnostic
)
assert(
	vim.fn.strdisplaywidth(with_diagnostic) == vim.fn.strdisplaywidth(two_git),
	"moving diagnostics into the fold rail must not add statuscolumn cells"
)
local diagnostic_result = rendered_statuscolumn_result()
local diagnostic_highlight_index
local isolated_count = 0
for index, highlight in ipairs(diagnostic_result.highlights) do
	if
		highlight.group:match("^DotfilesStatuscolumnSign%d+$")
		and vim.api.nvim_get_hl(0, { name = highlight.group, link = false }).fg == 0xff0000
	then
		diagnostic_highlight_index = index
	end
	if highlight.group:match("^DotfilesStatuscolumnSign%d+$") then
		isolated_count = isolated_count + 1
	end
end
assert(diagnostic_highlight_index ~= nil, "the diagnostic source foreground must be preserved")
assert(
	diagnostic_result.highlights[diagnostic_highlight_index - 1].group == "CursorLineFold",
	"a cursor-line diagnostic in the rail must retain the native fold-cell background"
)
assert(vim.api.nvim_get_hl(0, {
	name = diagnostic_result.highlights[diagnostic_highlight_index].group,
	link = false,
}).nocombine == true, "the diagnostic must not inherit number or fold sign styles")
assert(vim.api.nvim_get_hl(0, {
	name = diagnostic_result.highlights[diagnostic_highlight_index].group,
	link = false,
}).bg == vim.api.nvim_get_hl(0, {
	name = "DotfilesTestCursorLineFold",
	link = false,
}).bg, "the diagnostic cell must explicitly use the resolved cursor-line fold background")
assert(isolated_count == 2, "Git and the rail diagnostic must each isolate their source highlight")

vim.cmd.normal({ args = { "zc" }, bang = true })
assert(vim.fn.foldclosed(1) == 1, "the test fold must be closed")
assert(rendered_statuscolumn():sub(1, #"●") == "●", "a diagnostic must replace the closed-fold glyph too")
vim.cmd.normal({ args = { "zo" }, bang = true })

vim.api.nvim_buf_set_extmark(0, codex_namespace, 0, 0, {
	priority = 30,
	sign_text = "",
	sign_hl_group = "DiagnosticInfo",
})
local with_codex = rendered_statuscolumn_result()
assert(with_codex.str == with_diagnostic, "Codex must color the number without adding a sign cell")
assert(
	with_codex.str:match("^●%s+1[GS]$") ~= nil,
	"the combined row must render the rail diagnostic, number, and Git sign in order: " .. with_codex.str
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
vim.api.nvim_buf_set_extmark(0, diagnostic_namespace, 0, 0, {
	priority = 10,
	sign_text = "●",
	sign_hl_group = "DiagnosticSignError",
})
assert(
	rendered_statuscolumn():match("^●%s+1$") ~= nil,
	"a diagnostic outside folds must still occupy the fold rail cell"
)
vim.api.nvim_buf_clear_namespace(0, diagnostic_namespace, 0, -1)

local severity_namespace = vim.api.nvim_create_namespace("dotfiles-statuscolumn-severity-test")
vim.diagnostic.config({
	severity_sort = true,
	signs = {
		severity = { min = vim.diagnostic.severity.INFO },
		text = {
			[vim.diagnostic.severity.ERROR] = "󰄽",
			[vim.diagnostic.severity.WARN] = "󰄾",
			[vim.diagnostic.severity.INFO] = "+",
		},
	},
})
vim.diagnostic.set(severity_namespace, 0, {
	{ lnum = 0, col = 0, severity = vim.diagnostic.severity.WARN, message = "lower priority" },
	{ lnum = 0, col = 0, severity = vim.diagnostic.severity.ERROR, message = "highest priority" },
})
local strongest_diagnostic = rendered_statuscolumn_result()
assert(
	strongest_diagnostic.str:match("^󰄽%s+1$") ~= nil,
	"the strongest same-line diagnostic must represent the rail cell: " .. strongest_diagnostic.str
)
assert(
	vim.iter(strongest_diagnostic.highlights):any(function(highlight)
		return highlight.group:match("^DotfilesStatuscolumnSign%d+$")
			and vim.api.nvim_get_hl(0, { name = highlight.group, link = false }).fg
				== vim.api.nvim_get_hl(0, { name = "DiagnosticSignError", link = false }).fg
	end),
	"the representative diagnostic must retain the strongest severity highlight"
)
vim.diagnostic.reset(severity_namespace, 0)

vim.diagnostic.set(severity_namespace, 0, {
	{ lnum = 0, col = 0, severity = vim.diagnostic.severity.INFO, message = "information" },
})
local information_diagnostic = rendered_statuscolumn_result()
assert(
	information_diagnostic.str:match("^%+%s+1$") ~= nil,
	"an information diagnostic must use the plus glyph in the rail: " .. information_diagnostic.str
)
vim.diagnostic.reset(severity_namespace, 0)

local severities = {
	{ severity = vim.diagnostic.severity.ERROR, glyph = "󰄽", foreground = 0xff0000 },
	{ severity = vim.diagnostic.severity.WARN, glyph = "󰄾", foreground = 0xffff00 },
	{ severity = vim.diagnostic.severity.INFO, glyph = "+", foreground = 0x00ffff },
}
local function assert_diagnostic_background(result, expected)
	assert(result.str:sub(1, #expected.glyph) == expected.glyph, "unexpected diagnostic glyph: " .. result.str)
	local sign_index
	for index, highlight in ipairs(result.highlights) do
		if
			highlight.group:match("^DotfilesStatuscolumnSign%d+$")
			and vim.api.nvim_get_hl(0, { name = highlight.group, link = false }).fg == expected.foreground
		then
			sign_index = index
			break
		end
	end
	assert(sign_index ~= nil, "diagnostic highlight is missing: " .. vim.inspect(result))
	assert(
		result.highlights[sign_index - 1].group == expected.base,
		("expected %s beneath %s: %s"):format(expected.base, expected.glyph, vim.inspect(result.highlights))
	)
	assert(
		vim.api.nvim_get_hl(0, { name = result.highlights[sign_index].group, link = false }).bg
			== vim.api.nvim_get_hl(0, { name = expected.base, link = false }).bg,
		("the %s diagnostic cell must copy the %s background"):format(expected.glyph, expected.base)
	)
end

vim.api.nvim_win_set_cursor(0, { 4, 0 })
vim.cmd("1,4fold")
vim.cmd.normal({ args = { "zO" }, bang = true })
for _, item in ipairs(severities) do
	vim.diagnostic.set(severity_namespace, 0, {
		{ lnum = 1, col = 0, severity = item.severity, message = "inside fold" },
	})
	item.base = "FoldColumn"
	assert_diagnostic_background(rendered_statuscolumn_result(2), item)
	vim.diagnostic.reset(severity_namespace, 0)
end

vim.cmd.normal({ args = { "zE" }, bang = true })
for _, item in ipairs(severities) do
	vim.diagnostic.set(severity_namespace, 0, {
		{ lnum = 1, col = 0, severity = item.severity, message = "outside fold" },
	})
	item.base = "LineNr"
	assert_diagnostic_background(rendered_statuscolumn_result(2), item)
	vim.diagnostic.reset(severity_namespace, 0)
end

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
