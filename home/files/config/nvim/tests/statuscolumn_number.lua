local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
vim.opt.runtimepath:prepend(nvim_root)
vim.opt.runtimepath:append(vim.fn.stdpath("data") .. "/lazy/statuscol.nvim")
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")

local statuscolumn = require("config.statuscolumn")
vim.wo.numberwidth = 3
vim.wo.number = true
vim.wo.relativenumber = true
vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.fn["repeat"]({ "line" }, 1000))
vim.api.nvim_win_set_cursor(0, { 500, 0 })
statuscolumn.setup()

local function rendered_statuscolumn(win, lnum, maxwidth)
	vim.cmd.redrawstatus()
	return vim.api.nvim_eval_statusline(vim.wo[win].statuscolumn, {
		maxwidth = maxwidth or 20,
		use_statuscol_lnum = lnum,
		winid = win,
	}).str
end

local left = vim.api.nvim_get_current_win()
assert(rendered_statuscolumn(left, 500):match("500$") ~= nil, "current line must render its absolute number")
assert(rendered_statuscolumn(left, 499, 4) == "   󰄿", "upper marker must stay right-aligned in the number field")
assert(rendered_statuscolumn(left, 501, 4) == "   󰄼", "lower marker must stay right-aligned in the number field")

for _, case in ipairs({
	{ count = 9, cursor = 5 },
	{ count = 99, cursor = 50 },
	{ count = 999, cursor = 500 },
	{ count = 1000, cursor = 500 },
}) do
	vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.fn["repeat"]({ "line" }, case.count))
	vim.api.nvim_win_set_cursor(left, { case.cursor, 0 })
	local width = math.max(vim.wo[left].numberwidth, #tostring(case.count))
	local gutter_width = width + 1
	assert(
		rendered_statuscolumn(left, case.cursor, gutter_width) == " " .. string.format("%" .. width .. "d", case.cursor),
		("current number width must track a %d-line buffer"):format(case.count)
	)
	assert(
		rendered_statuscolumn(left, case.cursor - 1, gutter_width) == string.rep(" ", width) .. "󰄿",
		("upper marker width must track a %d-line buffer"):format(case.count)
	)
	assert(
		rendered_statuscolumn(left, case.cursor + 1, gutter_width) == string.rep(" ", width) .. "󰄼",
		("lower marker width must track a %d-line buffer"):format(case.count)
	)
end

vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.fn["repeat"]({ "line" }, 1000))
vim.api.nvim_win_set_cursor(left, { 500, 0 })

local args = {
	buf = 0,
	win = vim.api.nvim_get_current_win(),
	lnum = 500,
	relnum = 0,
	virtnum = 0,
	rnu = true,
}

assert(statuscolumn.number(args):match("%s*500$") ~= nil, "current relative line must remain absolute")
args.lnum, args.relnum = 499, 1
assert(statuscolumn.number(args):find("󰄿", 1, true), "line above the cursor must use the upper marker")
args.lnum, args.relnum = 501, 1
assert(statuscolumn.number(args):find("󰄼", 1, true), "line below the cursor must use the lower marker")
args.lnum, args.relnum = 480, 20
assert(statuscolumn.number(args):match("%s*20$") ~= nil, "other relative lines must render relative numbers")
args.rnu, args.lnum, args.relnum = false, 480, 20
assert(statuscolumn.number(args):match("%s*480$") ~= nil, "absolute mode must render absolute numbers")
args.virtnum = 1
assert(statuscolumn.number(args) == "    ", "virtual rows must pad to the grown number width")

vim.cmd.vsplit()
local right = vim.api.nvim_get_current_win()
vim.wo[right].number = true
vim.wo[right].relativenumber = true
vim.api.nvim_win_set_cursor(right, { 700, 0 })
assert(rendered_statuscolumn(right, 700):match("700$") ~= nil, "rendered split must use its own cursor number")
assert(
	statuscolumn.number({ buf = 0, win = right, lnum = 700, relnum = 0, virtnum = 0, rnu = true }):match("%s*700$")
		~= nil,
	"line numbers must use the cursor of the rendered split"
)

vim.wo.foldmethod = "manual"
vim.cmd("2,3fold")
local win = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_cursor(win, { 2, 0 })
vim.cmd.normal({ args = { "zO" }, bang = true })
assert(
	statuscolumn.fold({ lnum = 2, relnum = 0, virtnum = 0 }) == "%#CursorLineFold#",
	"an open fold must preserve the old one-cell marker"
)
assert(
	statuscolumn.fold({ lnum = 3, relnum = 1, virtnum = 0 }) == "%#FoldColumn# ",
	"a fold continuation must preserve the old one-cell separator"
)
assert(statuscolumn.fold({ lnum = 2, relnum = 0, virtnum = 1 }) == " ", "wrapped rows must leave fold space blank")
assert(_G.dotfiles_foldcolumn_click == statuscolumn.fold_click_handler, "fold clicks must bypass statuscol dispatch")
statuscolumn.fold_click({ button = "l", clicks = 2, mousepos = { winid = win, line = 2 } })
assert(vim.fn.foldclosed(2) == -1, "double click must not toggle a fold")
statuscolumn.fold_click({ button = "l", clicks = 1, mousepos = { winid = win, line = 2 } })
assert(vim.fn.foldclosed(2) == 2, "single click must toggle a fold")
assert(
	statuscolumn.fold({ lnum = 2, relnum = 0, virtnum = 0 }) == "%#CursorLineFold#",
	"a closed fold must preserve the old one-cell marker"
)

print("statuscolumn number regression: ok")
