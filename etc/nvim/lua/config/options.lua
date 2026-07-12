local opt = vim.opt

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
opt.relativenumber = true
opt.cursorline = true
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
