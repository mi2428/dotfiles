local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
local lazy_root = vim.fs.joinpath(vim.fn.stdpath("data"), "lazy")

vim.opt.runtimepath:prepend(nvim_root)
vim.opt.runtimepath:prepend(vim.fs.joinpath(lazy_root, "tiny-inline-diagnostic.nvim"))
vim.opt.runtimepath:prepend(vim.fs.joinpath(lazy_root, "nui.nvim"))
vim.opt.runtimepath:prepend(vim.fs.joinpath(lazy_root, "noice.nvim"))
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")

local tiny = require("tiny-inline-diagnostic")
tiny.setup()
local ui = require("config.noice_ui")
ui.setup()

local SearchCount = require("noice.view.backend.dotfiles_search_count")
local Message = require("noice.message")
local view = SearchCount({ view = "search_count" })
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "apple apple apple", "apple" })
vim.o.hlsearch = true
vim.fn.setreg("/", "apple")
vim.cmd("normal! gg0n")
view:set(Message("msg_show", "search_count", "/apple [2/4]"), { format = false })
view:show()

local noice_ns = require("noice.config").ns
local function options()
	local mark = vim.api.nvim_buf_get_extmark_by_id(buf, noice_ns, view.extmark, { details = true })
	return mark[3]
end

assert(options().virt_text_pos == "eol", "the chip must start at EOL when no diagnostic is present")
assert(options().virt_text[1][1]:find("", 1, true), "the standalone chip must own its relation arrow")

local diagnostic_ns = vim.api.nvim_create_namespace("DotfilesNoiceFollowLayoutDiagnostics")
vim.diagnostic.set(diagnostic_ns, buf, {
	{ lnum = 0, col = 0, severity = vim.diagnostic.severity.ERROR, message = "Unexpected <exp>." },
	{ lnum = 0, col = 0, severity = vim.diagnostic.severity.WARN, message = "Undefined global `apple`." },
})
require("tiny-inline-diagnostic.renderer").safe_render(tiny.config, buf)
vim.api.nvim_exec_autocmds("DiagnosticChanged", { buffer = buf, modeline = false })
assert(
	vim.wait(1000, function()
		return view.extmark and options().virt_lines ~= nil
	end),
	"a newly colliding diagnostic must move the search chip above the line"
)

local collided = options()
assert(collided.virt_text == nil and collided.virt_lines_above, "the collision layout must not retain EOL text")
local collision_text = table.concat(vim.tbl_map(function(chunk)
	return chunk[1]
end, collided.virt_lines[1]))
assert(not collision_text:find("", 1, true), "the aligned chip must leave the relation arrow to diagnostics")
assert(collision_text:find("", 1, true) and collision_text:find("", 1, true), "the moved chip needs both caps")

vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.api.nvim_exec_autocmds("CursorMoved", { modeline = false })
require("tiny-inline-diagnostic.renderer").safe_render(tiny.config, buf)
assert(
	vim.wait(1000, function()
		return view.extmark and options().virt_text ~= nil
	end),
	"moving to a non-diagnostic match must redraw the chip at that match's EOL"
)
assert(options().virt_text[1][1]:find("", 1, true), "the non-colliding match must regain its own arrow")

vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.api.nvim_exec_autocmds("CursorMoved", { modeline = false })
require("tiny-inline-diagnostic.renderer").safe_render(tiny.config, buf)
assert(
	vim.wait(1000, function()
		return view.extmark and options().virt_lines ~= nil
	end),
	"returning to the diagnostic match must restore the aligned collision layout"
)

vim.diagnostic.reset(diagnostic_ns, buf)
require("tiny-inline-diagnostic.cache").clear(buf)
require("tiny-inline-diagnostic.renderer").safe_render(tiny.config, buf)
vim.api.nvim_exec_autocmds("DiagnosticChanged", { buffer = buf, modeline = false })
assert(
	vim.wait(1000, function()
		return view.extmark and options().virt_text ~= nil
	end),
	"clearing diagnostics must return the search chip to EOL"
)
assert(options().virt_text[1][1]:find("", 1, true), "the restored standalone chip must regain its arrow")

view:hide()
print("Noice search diagnostic-layout lifecycle regression: ok")
