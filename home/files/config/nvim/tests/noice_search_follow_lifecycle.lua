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
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "apple apple apple", "nothing", "apple" })
vim.o.hlsearch = true
vim.fn.setreg("/", "apple")
vim.cmd("normal! gg0n")

view:set(Message("msg_show", "search_count", "/apple [2/4]"), { format = false })
view:show()
assert(view.extmark, "show() must render the native count immediately")
assert(#vim.api.nvim_get_autocmds({ group = view.augroup }) > 0, "show() must install its movement lifecycle")

local original_evaluate = ui.evaluate_search_count
local calls = 0
ui.evaluate_search_count = function()
	calls = calls + 1
	return { current = 2, total = 4, exact_match = 1, incomplete = 0 }
end

local started = vim.uv.hrtime()
for _ = 1, 10000 do
	vim.api.nvim_exec_autocmds("CursorMoved", { modeline = false })
end
local enqueue_ms = (vim.uv.hrtime() - started) / 1e6
assert(view.extmark == nil, "the stale chip must disappear on the first movement event")
assert(
	vim.wait(1000, function()
		return calls == 1 and view.extmark ~= nil
	end),
	"a movement burst must settle into one refresh"
)
assert(calls == 1, "10,000 CursorMoved events must trigger exactly one searchcount recomputation")
assert(enqueue_ms < 1000, ("movement scheduling was unexpectedly expensive: %.2fms"):format(enqueue_ms))

local calls_before_hide = calls
vim.api.nvim_exec_autocmds("CursorMoved", { modeline = false })
view:hide()
vim.wait(ui.search_count_debounce_ms + 100)
assert(calls == calls_before_hide, "a timer queued before hide() must not resurrect the chip")
assert(view.extmark == nil and view.timer == nil and view.augroup == nil, "hide() must release all tracking state")

view:show()
local other_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(other_buf)
assert(view.extmark == nil, "leaving the source buffer must clear its chip immediately")
local calls_outside_source = calls
vim.api.nvim_exec_autocmds("CursorMoved", { modeline = false })
vim.wait(ui.search_count_debounce_ms + 100)
assert(calls == calls_outside_source, "another buffer must not recompute the source buffer's search count")
vim.api.nvim_set_current_buf(buf)
assert(
	vim.wait(1000, function()
		return view.extmark ~= nil
	end),
	"returning to the unchanged source window must restore the exact-match chip"
)
vim.api.nvim_buf_delete(other_buf, { force = true })

local source_group = view.augroup
vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "changed" })
vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf, modeline = false })
local calls_before_edit_wait = calls
vim.wait(ui.search_count_debounce_ms + 100)
assert(view.extmark == nil, "editing after the search must invalidate the stale chip")
assert(calls == calls_before_edit_wait, "an edited buffer must not be rescanned with a stale search message")
assert(#vim.api.nvim_get_autocmds({ group = source_group }) > 0, "invalidating a chip must keep lifecycle tracking")

view:hide()
for _ = 1, 100 do
	view:show()
	view:hide()
end
assert(view.timer == nil and view.augroup == nil, "repeated show/hide cycles must not leak timers or autocmd groups")

ui.evaluate_search_count = original_evaluate
print(("Noice search lifecycle regression: ok (10k events %.2fms, one recompute)"):format(enqueue_ms))
