local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
local lazy_root = vim.fs.joinpath(vim.fn.stdpath("data"), "lazy")

vim.opt.runtimepath:prepend(nvim_root)
vim.opt.runtimepath:prepend(vim.fs.joinpath(lazy_root, "nui.nvim"))
vim.opt.runtimepath:prepend(vim.fs.joinpath(lazy_root, "noice.nvim"))
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")

local ui = require("config.noice_ui")
ui.setup()

local SearchCount = require("noice.view.backend.dotfiles_search_count")
local Message = require("noice.message")
local view = SearchCount({ view = "search_count" })
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
	"apple apple",
	"\t日本語apple終端",
	"delimiter",
	"apple",
})
vim.o.hlsearch = true
vim.fn.setreg("/", "apple")
vim.cmd("normal! gg0n")

local function extmark_details()
	if not view.extmark then
		return
	end
	local mark = vim.api.nvim_buf_get_extmark_by_id(buf, require("noice.config").ns, view.extmark, { details = true })
	return mark[1], mark[2], mark[3]
end

local function refresh_at(row, col)
	vim.api.nvim_win_set_cursor(0, { row, col })
	vim.api.nvim_exec_autocmds("CursorMoved", { modeline = false })
	vim.wait(1000, function()
		return view.extmark ~= nil
	end)
end

view:set(Message("msg_show", "search_count", "/apple [2/4]"), { format = false })
view:show()

refresh_at(1, 0)
local row, _, details = extmark_details()
assert(row == 0 and details.virt_text, "the first exact match must render inline on its own row")

refresh_at(1, 2)
assert(view.extmark, "the chip must remain visible in the middle of an exact match")

vim.api.nvim_win_set_cursor(0, { 1, 5 })
vim.api.nvim_exec_autocmds("CursorMoved", { modeline = false })
vim.wait(ui.search_count_debounce_ms + 100)
assert(view.extmark == nil, "the delimiter between matches must not retain a stale chip")

refresh_at(1, 6)
local _, _, second_details = extmark_details()
local second_text = table.concat(vim.tbl_map(function(chunk)
	return chunk[1]
end, second_details.virt_text))
assert(second_text:find("Match 2 of 4", 1, true), "an adjacent hit must recompute its ordinal")

refresh_at(2, 12)
assert(view.extmark, "a multibyte line containing a tab must support exact-match tracking")

refresh_at(4, 0)
local final_row = extmark_details()
assert(final_row == 3, "the final match must move the chip to the current line")

view:hide()
view:set(Message("msg_show", "search_count", "?apple [4/4]"), { format = false })
view:show()
local reverse = ui.search_count_virtual_text(view.last_message)
assert(reverse[4][1] == " ", "reverse search tracking must retain Noice's upward search icon")

vim.cmd("nohlsearch")
vim.api.nvim_exec_autocmds("CmdlineLeave", { modeline = false })
vim.wait(100)
assert(view.extmark == nil, ":nohlsearch must remove the chip without waiting for cursor movement")

view:hide()
print("Noice search runtime tracking regression: ok")
