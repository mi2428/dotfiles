local catppuccin = require("config.catppuccin")
local opt = vim.opt
local colors = catppuccin.palette()
local mode_styles = {}

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

local function blend(fg, bg, alpha)
	local function hex_to_rgb(hex)
		hex = hex:gsub("#", "")
		return {
			tonumber(hex:sub(1, 2), 16),
			tonumber(hex:sub(3, 4), 16),
			tonumber(hex:sub(5, 6), 16),
		}
	end

	local function rgb_to_hex(rgb)
		return string.format("#%02x%02x%02x", rgb[1], rgb[2], rgb[3])
	end

	local fg_rgb = hex_to_rgb(fg)
	local bg_rgb = hex_to_rgb(bg)
	local out = {}

	for index = 1, 3 do
		out[index] = math.floor((alpha * fg_rgb[index]) + ((1 - alpha) * bg_rgb[index]) + 0.5)
	end

	return rgb_to_hex(out)
end

local function refresh_mode_styles()
	colors = catppuccin.palette()
	mode_styles = {
		default = {
			fg = colors.lavender,
			bg = blend(colors.lavender, colors.base, 0.28),
		},
		command = {
			fg = colors.yellow,
			bg = blend(colors.yellow, colors.base, 0.28),
		},
		copy = {
			fg = colors.yellow,
			bg = blend(colors.yellow, colors.base, 0.18),
		},
		delete = {
			fg = colors.red,
			bg = blend(colors.red, colors.base, 0.18),
		},
		change = {
			fg = colors.peach,
			bg = blend(colors.peach, colors.base, 0.18),
		},
		format = {
			fg = colors.rosewater,
			bg = blend(colors.rosewater, colors.base, 0.18),
		},
		insert = {
			fg = colors.teal,
			bg = blend(colors.teal, colors.base, 0.26),
		},
		replace = {
			fg = colors.blue,
			bg = blend(colors.blue, colors.base, 0.26),
		},
		select = {
			fg = colors.mauve,
			bg = blend(colors.mauve, colors.base, 0.2),
		},
		visual = {
			fg = colors.mauve,
			bg = blend(colors.mauve, colors.base, 0.3),
		},
	}
end

local function cursorline_enabled(buf)
	local ignored_filetypes = {
		DiffviewFiles = true,
		dashboard = true,
		fzf = true,
		help = true,
		lazy = true,
		lspinfo = true,
		man = true,
		mason = true,
		oil = true,
		prompt = true,
		qf = true,
		snacks_dashboard = true,
		terminal = true,
		toggleterm = true,
		Trouble = true,
	}

	return vim.bo[buf].buftype == "" and ignored_filetypes[vim.bo[buf].filetype] ~= true
end

local function current_mode_scene()
	local mode = vim.api.nvim_get_mode().mode
	if mode:match("^c") then
		return "command"
	end

	if mode:match("^i") then
		return "insert"
	end

	if mode:match("^[Rr]") then
		return "replace"
	end

	if mode:match("^[vV\22]") then
		return "visual"
	end

	if mode:match("^[sS\19]") then
		return "select"
	end

	if mode:match("^no") then
		local operator = vim.v.operator or ""
		if operator == "y" then
			return "copy"
		end
		if operator == "d" then
			return "delete"
		end
		if operator == "c" then
			return "change"
		end
		if operator:match("[=!><g]") then
			return "format"
		end
	end

	return "default"
end

local function set_statuscolumn_highlights(scene)
	scene = scene or "default"
	local style = mode_styles[scene] or mode_styles.default

	vim.api.nvim_set_hl(0, "LineNr", { fg = colors.overlay0 })
	vim.api.nvim_set_hl(0, "Visual", { bg = blend(colors.mauve, colors.base, 0.4), bold = true })
	vim.api.nvim_set_hl(0, "CursorLine", { bg = style.bg })
	vim.api.nvim_set_hl(0, "CursorLineSign", { bg = style.bg })
	vim.api.nvim_set_hl(0, "CursorLineFold", { bg = style.bg })
	vim.api.nvim_set_hl(0, "CursorLineNr", { fg = style.fg, bg = style.bg, bold = true })

	local cursorline = vim.api.nvim_get_hl(0, { name = "CursorLineNr", link = false })
	if not cursorline or vim.tbl_isempty(cursorline) then
		vim.api.nvim_set_hl(0, "DotfilesStatuscolumnMarker", { link = "CursorLineNr", default = false })
		return
	end

	cursorline.bold = true
	vim.api.nvim_set_hl(0, "DotfilesStatuscolumnMarker", cursorline)
end

local function apply_mode_ui()
	local win = vim.api.nvim_get_current_win()
	local buf = vim.api.nvim_get_current_buf()
	if not vim.api.nvim_win_is_valid(win) or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	if cursorline_enabled(buf) then
		vim.wo[win].cursorline = true
		set_statuscolumn_highlights(current_mode_scene())
	else
		vim.wo[win].cursorline = false
		set_statuscolumn_highlights("default")
	end
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
opt.foldcolumn = "auto:1"
opt.foldlevel = 99
opt.foldlevelstart = 99
opt.foldenable = true
opt.showtabline = 2
opt.showmode = false
opt.signcolumn = "yes:1"
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
	tab = "»·",
	trail = "·",
	eol = "↵",
	extends = "⟩",
	precedes = "⟨",
	nbsp = "⍽",
}

opt.splitbelow = true
opt.splitright = true
opt.updatetime = 200
opt.completeopt = { "menu", "menuone", "noselect" }

vim.api.nvim_create_autocmd("ColorScheme", {
	group = vim.api.nvim_create_augroup("dotfiles-statuscolumn-highlights", { clear = true }),
	pattern = "*",
	callback = function()
		refresh_mode_styles()
		apply_mode_ui()
	end,
})
refresh_mode_styles()
apply_mode_ui()

vim.api.nvim_create_autocmd({ "BufEnter", "FileType", "ModeChanged", "WinEnter" }, {
	group = vim.api.nvim_create_augroup("dotfiles-cursorline-mode", { clear = true }),
	callback = function()
		vim.schedule(apply_mode_ui)
	end,
})

vim.api.nvim_create_autocmd("CmdlineEnter", {
	group = vim.api.nvim_create_augroup("dotfiles-cursorline-command", { clear = true }),
	callback = function()
		set_statuscolumn_highlights("command")
		-- The editing grid is otherwise left with its pre-command-line colors.
		vim.cmd.redraw({ bang = true })
	end,
})

vim.api.nvim_create_autocmd("CmdlineLeave", {
	group = "dotfiles-cursorline-command",
	callback = function()
		vim.schedule(apply_mode_ui)
	end,
})

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
