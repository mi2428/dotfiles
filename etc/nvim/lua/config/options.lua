local catppuccin = require("config.catppuccin")
local opt = vim.opt
local colors = catppuccin.palette()

vim.g.mapleader = " "
vim.g.maplocalleader = " "

local bundled_lua_parser = vim.fs.joinpath(vim.env.VIMRUNTIME, "parser", "lua.so")
if vim.uv.fs_stat(bundled_lua_parser) then
	-- Neovim 0.12 ships a Lua parser newer than some plugin-managed copies.
	-- Prefer the bundled parser to avoid query/parser mismatches on startup.
	pcall(vim.treesitter.language.add, "lua", { path = bundled_lua_parser })
end

local function patch_lua_highlights_query()
	local ok, info = pcall(vim.treesitter.language.inspect, "lua")
	if not ok or not info or vim.tbl_contains(info.fields or {}, "operator") then
		return
	end

	local query_path = vim.fs.joinpath(vim.env.VIMRUNTIME, "queries", "lua", "highlights.scm")
	if not vim.uv.fs_stat(query_path) then
		return
	end

	local query = table.concat(vim.fn.readfile(query_path), "\n")
	local old = [[(binary_expression
  operator: _ @operator)

(unary_expression
  operator: _ @operator)

"=" @operator]]
	local new = [[[
  "+"
  "-"
  "*"
  "/"
  "%"
  "^"
  "#"
  "&"
  "~"
  "|"
  "<<"
  ">>"
  "//"
  ".."
  "<"
  "<="
  ">"
  ">="
  "=="
  "~="
] @operator

"=" @operator]]

	query = query:gsub(old, new, 1)
	pcall(vim.treesitter.query.set, "lua", "highlights", query)
end

patch_lua_highlights_query()

local function set_statuscolumn_highlights()
	vim.api.nvim_set_hl(0, "CursorLineNr", { fg = colors.peach, bold = true })

	local cursorline = vim.api.nvim_get_hl(0, { name = "CursorLineNr", link = false })
	if not cursorline or vim.tbl_isempty(cursorline) then
		vim.api.nvim_set_hl(0, "DotfilesStatuscolumnMarker", { link = "CursorLineNr", default = false })
		return
	end

	cursorline.bold = true
	vim.api.nvim_set_hl(0, "DotfilesStatuscolumnMarker", cursorline)
end

local function statuscolumn_number_width()
	return math.max(vim.wo.numberwidth, #tostring(vim.fn.line("$")))
end

local function statuscolumn_padding()
	return string.rep(" ", statuscolumn_number_width())
end

local function statuscolumn_marker(width, marker)
	return "%#DotfilesStatuscolumnMarker#" .. string.format("%" .. width .. "s", marker)
end

local function set_relative_number(enabled)
	vim.opt_local.relativenumber = enabled
end

function _G.dotfiles_statuscolumn()
	if vim.v.virtnum ~= 0 then
		return statuscolumn_padding()
	end

	local width = statuscolumn_number_width()
	local current = vim.fn.line(".")
	local line = vim.v.lnum
	local relnum = vim.v.relnum
	local relative_mode = vim.wo.relativenumber

	if not relative_mode then
		local number_hl = line == current and "%#CursorLineNr#" or "%#LineNr#"
		return number_hl .. string.format("%" .. width .. "d", line)
	end

	if line == current - 1 then
		return statuscolumn_marker(width, "󰄿")
	end

	if line == current then
		return "%#CursorLineNr#" .. string.format("%" .. width .. "d", line)
	end

	if line == current + 1 then
		return statuscolumn_marker(width, "󰄼")
	end

	return "%#LineNr#" .. string.format("%" .. width .. "d", relnum)
end

opt.termguicolors = true
opt.background = "dark"
opt.clipboard = "unnamedplus"
opt.history = 1000
opt.mouse = "a"
opt.timeout = true
opt.timeoutlen = 300
opt.ttimeout = true
opt.ttimeoutlen = 0

opt.number = true
opt.numberwidth = 3
opt.relativenumber = true
opt.statuscolumn = "%s%=%{%v:lua.dotfiles_statuscolumn()%}"
opt.cursorline = true
opt.foldcolumn = "1"
opt.foldlevel = 99
opt.foldlevelstart = 99
opt.foldenable = true
opt.showtabline = 2
opt.showmode = false
opt.signcolumn = "yes"
opt.scrolloff = 8
opt.sidescrolloff = 4

opt.smartcase = true
opt.ignorecase = true
opt.hlsearch = true
opt.incsearch = true

opt.autoindent = true
opt.smartindent = true
opt.expandtab = true
opt.tabstop = 2
opt.shiftwidth = 2
opt.softtabstop = 2
opt.breakindent = true

opt.list = true
opt.listchars = {
	tab = "»-",
	trail = "-",
	eol = "↲",
	extends = "»",
	precedes = "«",
	nbsp = "%",
}

opt.splitbelow = true
opt.splitright = true
opt.updatetime = 200
opt.completeopt = { "menu", "menuone", "noselect" }

vim.api.nvim_create_autocmd("ColorScheme", {
	group = vim.api.nvim_create_augroup("dotfiles-statuscolumn-highlights", { clear = true }),
	pattern = "*",
	callback = set_statuscolumn_highlights,
})
set_statuscolumn_highlights()

vim.api.nvim_create_autocmd("InsertEnter", {
	group = vim.api.nvim_create_augroup("dotfiles-relative-number-mode", { clear = true }),
	callback = function()
		set_relative_number(false)
	end,
})

vim.api.nvim_create_autocmd("InsertLeave", {
	group = "dotfiles-relative-number-mode",
	callback = function()
		set_relative_number(true)
	end,
})
