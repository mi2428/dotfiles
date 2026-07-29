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

local chunks = require("config.noice_ui").search_count_virtual_text("/apple [1/3]")
local arrow = vim.api.nvim_get_hl(0, { name = chunks[1][2], link = false })
local left_cap = vim.api.nvim_get_hl(0, { name = chunks[2][2], link = false })
local body = vim.api.nvim_get_hl(0, { name = chunks[3][2], link = false })
local right_cap = vim.api.nvim_get_hl(0, { name = chunks[#chunks][2], link = false })

assert(arrow.bg == nil, "the arrow must expose the real window background")
assert(left_cap.bg == nil and right_cap.bg == nil, "both half-moon glyphs must expose the real window background")
assert(body.bg ~= nil, "the search body must retain the tiny-inline-diagnostic filled chip color")
assert(
	left_cap.fg == body.bg and right_cap.fg == body.bg,
	"the half-moon foreground must exactly continue the filled chip body"
)

vim.api.nvim_set_hl(0, "Normal", { fg = 0xcdd6f4, bg = 0x11111b })
vim.api.nvim_set_hl(0, "CursorLine", { bg = 0x313244 })
arrow = vim.api.nvim_get_hl(0, { name = chunks[1][2], link = false })
left_cap = vim.api.nvim_get_hl(0, { name = chunks[2][2], link = false })
assert(arrow.bg == nil and left_cap.bg == nil, "caps must not bake in either Normal or CursorLine backgrounds")

print("Noice search highlight regression: ok")
