local opt = vim.opt

vim.g.mapleader = " "
vim.g.maplocalleader = " "

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
