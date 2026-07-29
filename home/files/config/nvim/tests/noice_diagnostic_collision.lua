local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
local lazy_root = vim.fs.joinpath(vim.fn.stdpath("data"), "lazy")

vim.opt.runtimepath:prepend(nvim_root)
vim.opt.runtimepath:prepend(vim.fs.joinpath(lazy_root, "tiny-inline-diagnostic.nvim"))
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")

local tiny = require("tiny-inline-diagnostic")
tiny.setup()

local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "apple apple apple", "return foo" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })

local ui = require("config.noice_ui")
local no_diagnostic = ui.search_count_extmark_options(buf, 0, "/apple [1/3]")
assert(no_diagnostic.virt_text_pos == "eol", "Search counts should stay inline when the EOL is free")
assert(no_diagnostic.virt_lines == nil, "Search counts without diagnostics need no extra screen row")
assert(no_diagnostic.hl_mode == "combine", "Search count caps must blend with the actual editor background")
assert(
	no_diagnostic.virt_text[1][2] == "TinyInlineDiagnosticVirtualTextArrowNoBg"
		and no_diagnostic.virt_text[2][2] == "TinyInlineInvDiagnosticVirtualTextInfoNoBg"
		and no_diagnostic.virt_text[#no_diagnostic.virt_text][2] == "TinyInlineInvDiagnosticVirtualTextInfoNoBg",
	"Search arrows and rounded caps must not inherit tiny-inline-diagnostic's CursorLine background"
)

local diagnostic_ns = vim.api.nvim_create_namespace("DotfilesNoiceCollisionDiagnostics")
vim.diagnostic.set(diagnostic_ns, buf, {
	{ lnum = 0, col = 0, severity = vim.diagnostic.severity.ERROR, message = "Unexpected <exp>." },
	{ lnum = 0, col = 0, severity = vim.diagnostic.severity.WARN, message = "Undefined global `apple`." },
})
require("tiny-inline-diagnostic.renderer").safe_render(tiny.config, buf)

local tiny_ns = assert(vim.api.nvim_get_namespaces().TinyInlineDiagnostic)
local diagnostic_marks = vim.api.nvim_buf_get_extmarks(buf, tiny_ns, 0, -1, { details = true })
assert(#diagnostic_marks == 2, "Both diagnostics must remain rendered before placing the search status")
local function extmark_text(mark)
	return table.concat(vim.tbl_map(function(chunk)
		return chunk[1]
	end, mark[4].virt_text))
end
local function chunks_text(chunks)
	return table.concat(vim.tbl_map(function(chunk)
		return chunk[1]
	end, chunks))
end
local first_diagnostic = extmark_text(diagnostic_marks[1])
local last_diagnostic = extmark_text(diagnostic_marks[2])
assert(
	first_diagnostic:find("", 1, true) and not first_diagnostic:find("", 1, true),
	"The first of multiple diagnostics must own only the left rounded cap"
)
assert(
	last_diagnostic:find("", 1, true) and not last_diagnostic:find("", 1, true),
	"The last of multiple diagnostics must own only the right rounded cap"
)

local with_diagnostics = ui.search_count_extmark_options(buf, 0, "/apple [1/3]")
assert(with_diagnostics.virt_text == nil, "Search counts must not compete for a diagnostic-owned EOL")
assert(with_diagnostics.virt_lines_above == true, "Search counts must move to a separate row above diagnostics")
assert(#with_diagnostics.virt_lines == 1, "A diagnostic collision should add exactly one transient row")

local chunks = with_diagnostics.virt_lines[1]
local diagnostic_chip_col = diagnostic_marks[1][4].virt_text_win_col
	+ vim.fn.strdisplaywidth(diagnostic_marks[1][4].virt_text[1][1])
assert(
	vim.fn.strdisplaywidth(chunks[1][1]) == diagnostic_chip_col,
	"The search and diagnostic chips must start in the same window column"
)
assert(chunks[2][1] == "", "The collision-safe row must retain its rounded left cap")
assert(chunks[#chunks][1] == "", "The collision-safe row must retain its rounded right cap")
assert(chunks[4][1] == " ", "The collision-safe row must use the Noice search icon")
assert(chunks[5][1] == " Match 1 of 3 ", "The collision-safe row must retain the readable match count")
assert(
	not chunks_text(vim.list_slice(chunks, 2)):find("", 1, true),
	"The aligned search chip must leave the shared relation arrow to the diagnostic"
)
assert(
	vim.deep_equal(diagnostic_marks, vim.api.nvim_buf_get_extmarks(buf, tiny_ns, 0, -1, { details = true })),
	"Moving the search status must not rewrite diagnostic cap ownership"
)

print("Noice and tiny-inline-diagnostic collision regression: ok")
