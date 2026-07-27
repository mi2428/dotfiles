local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
local lazy_root = vim.fs.joinpath(vim.fn.stdpath("data"), "lazy")
vim.opt.runtimepath:prepend(nvim_root)
vim.opt.runtimepath:append(vim.fs.joinpath(lazy_root, "heirline.nvim"))
vim.opt.runtimepath:append(vim.fs.joinpath(lazy_root, "catppuccin"))
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")

require("catppuccin").setup({ flavour = "mocha" })
vim.cmd.colorscheme("catppuccin-mocha")

local original_get_clients = vim.lsp.get_clients
vim.lsp.get_clients = function()
	return { { name = "diagnostic-palette-test" } }
end

local namespace = vim.api.nvim_create_namespace("dotfiles-heirline-diagnostic-palette-test")
vim.diagnostic.set(namespace, 0, {
	{ lnum = 0, col = 0, severity = vim.diagnostic.severity.ERROR, message = "error" },
	{ lnum = 0, col = 0, severity = vim.diagnostic.severity.WARN, message = "warning" },
	{ lnum = 0, col = 0, severity = vim.diagnostic.severity.INFO, message = "information" },
	{ lnum = 0, col = 0, severity = vim.diagnostic.severity.HINT, message = "hint" },
})

vim.o.columns = 180
require("config.heirline_statusline").setup()
local rendered = vim.api.nvim_eval_statusline(vim.o.statusline, {
	winid = vim.api.nvim_get_current_win(),
	maxwidth = 180,
}).str

for _, glyph in ipairs({ "󰅚", "󰀪", "󰋽", "󰌵" }) do
	assert(rendered:find(glyph, 1, true), "missing outline diagnostic glyph " .. glyph .. ": " .. rendered)
end

local colors = require("catppuccin.palettes").get_palette("mocha")
local expected = {
	Error = colors.red,
	Warn = colors.yellow,
	Info = colors.sky,
	Hint = colors.teal,
}
local function numeric(color)
	return tonumber(color:sub(2), 16)
end

for severity, color in pairs(expected) do
	local heirline = vim.api.nvim_get_hl(0, { name = "DotfilesDiagnostic" .. severity, link = false })
	local editor = vim.api.nvim_get_hl(0, { name = "DiagnosticSign" .. severity, link = false })
	assert(heirline.fg == numeric(color), severity .. " heirline icon does not match its Catppuccin color")
	assert(editor.fg == numeric(color), severity .. " editor sign does not match its Catppuccin color")
end

vim.lsp.get_clients = original_get_clients
print("heirline diagnostic palette regression: ok")
