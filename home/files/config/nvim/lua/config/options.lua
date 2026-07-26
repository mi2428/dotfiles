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

local function mode_highlight_group(base, scene)
	local suffix = (scene or "default"):gsub("^%l", string.upper)
	return "Dotfiles" .. base .. suffix
end

local function refresh_statuscolumn_highlights()
	vim.api.nvim_set_hl(0, "LineNr", { fg = colors.overlay0 })
	vim.api.nvim_set_hl(0, "Visual", { bg = blend(colors.mauve, colors.base, 0.4), bold = true })

	for scene, style in pairs(mode_styles) do
		vim.api.nvim_set_hl(0, mode_highlight_group("CursorLine", scene), { bg = style.bg })
		vim.api.nvim_set_hl(0, mode_highlight_group("CursorLineSign", scene), { bg = style.bg })
		vim.api.nvim_set_hl(0, mode_highlight_group("CursorLineFold", scene), { bg = style.bg })
		vim.api.nvim_set_hl(
			0,
			mode_highlight_group("CursorLineNr", scene),
			{ fg = style.fg, bg = style.bg, bold = true }
		)
		vim.api.nvim_set_hl(
			0,
			mode_highlight_group("StatuscolumnMarker", scene),
			{ fg = style.fg, bg = style.bg, bold = true }
		)
	end

	local default = mode_styles.default
	vim.api.nvim_set_hl(0, "CursorLine", { bg = default.bg })
	vim.api.nvim_set_hl(0, "CursorLineSign", { bg = default.bg })
	vim.api.nvim_set_hl(0, "CursorLineFold", { bg = default.bg })
	vim.api.nvim_set_hl(0, "CursorLineNr", { fg = default.fg, bg = default.bg, bold = true })
	vim.api.nvim_set_hl(0, "DotfilesStatuscolumnMarker", { fg = default.fg, bg = default.bg, bold = true })
end

local function set_window_highlights(win, scene)
	-- CursorLine groups are global, so point them at scene-specific groups via
	-- the window-local override instead of recoloring every split at once.
	local replacements = {
		CursorLine = mode_highlight_group("CursorLine", scene),
		CursorLineSign = mode_highlight_group("CursorLineSign", scene),
		CursorLineFold = mode_highlight_group("CursorLineFold", scene),
		CursorLineNr = mode_highlight_group("CursorLineNr", scene),
		DotfilesStatuscolumnMarker = mode_highlight_group("StatuscolumnMarker", scene),
	}
	local entries = {}
	local indexes = {}

	for entry in vim.wo[win].winhighlight:gmatch("[^,]+") do
		local source = entry:match("^([^:]+):")
		if source then
			indexes[source] = #entries + 1
		end
		entries[#entries + 1] = entry
	end

	for source, target in pairs(replacements) do
		local entry = source .. ":" .. target
		if indexes[source] then
			entries[indexes[source]] = entry
		else
			entries[#entries + 1] = entry
		end
	end

	vim.wo[win].winhighlight = table.concat(entries, ",")
end

local window_scenes = {}

local function apply_mode_ui(win, scene)
	win = win or vim.api.nvim_get_current_win()
	local buf = vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) or -1
	if not vim.api.nvim_win_is_valid(win) or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	scene = scene or window_scenes[win] or "default"
	if cursorline_enabled(buf) then
		vim.wo[win].cursorline = true
	else
		vim.wo[win].cursorline = false
		scene = "default"
	end

	window_scenes[win] = scene
	set_window_highlights(win, scene)
end

local function schedule_current_mode_ui()
	local win = vim.api.nvim_get_current_win()
	local scene = current_mode_scene()
	vim.schedule(function()
		apply_mode_ui(win, scene)
	end)
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

local fold_symbols = {
	close = "",
	open = "",
	sep = " ",
}

function _G.dotfiles_foldcolumn()
	if vim.v.virtnum ~= 0 then
		return " "
	end

	local line = vim.v.lnum
	local level = vim.fn.foldlevel(line)
	if level == 0 then
		return " "
	end

	local symbol = fold_symbols.sep
	if vim.fn.foldclosed(line) == line then
		symbol = fold_symbols.close
	elseif line == 1 or level > vim.fn.foldlevel(line - 1) then
		symbol = fold_symbols.open
	end

	local highlight = vim.v.relnum == 0 and "%#CursorLineFold#" or "%#FoldColumn#"
	return highlight .. symbol
end

function _G.dotfiles_foldcolumn_click(_, clicks, button)
	-- Neovim reports rapid clicks as 1, 2, 3, 4. Handling every
	-- event would toggle twice on a double-click and look like a no-op.
	if button ~= "l" or clicks ~= 1 then
		return
	end

	local mouse = vim.fn.getmousepos()
	if mouse.winid == 0 or mouse.line == 0 then
		return
	end

	vim.api.nvim_win_call(mouse.winid, function()
		if vim.fn.foldlevel(mouse.line) == 0 then
			return
		end
		vim.api.nvim_win_set_cursor(mouse.winid, { mouse.line, 0 })
		local command = vim.fn.foldclosed(mouse.line) == -1 and "zc" or "zo"
		vim.cmd.normal({ args = { command }, bang = true })
	end)
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
opt.fillchars:append({
	fold = " ",
	foldopen = fold_symbols.open,
	foldclose = fold_symbols.close,
	foldsep = fold_symbols.sep,
})
opt.statuscolumn =
	"%@v:lua.dotfiles_foldcolumn_click@%{%v:lua.dotfiles_foldcolumn()%}%T%s%=%{%v:lua.dotfiles_statuscolumn()%}"
opt.cursorline = true
opt.foldcolumn = "auto:1"
opt.foldlevel = 99
opt.foldlevelstart = 99
opt.foldenable = true
opt.showtabline = 2
opt.showmode = false
-- Collapse unused sign slots, but expand to keep two concurrent signs visible.
opt.signcolumn = "auto:2"
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
		refresh_statuscolumn_highlights()
		for _, win in ipairs(vim.api.nvim_list_wins()) do
			apply_mode_ui(win)
		end
	end,
})
refresh_mode_styles()
refresh_statuscolumn_highlights()
apply_mode_ui(vim.api.nvim_get_current_win(), current_mode_scene())

vim.api.nvim_create_autocmd({ "BufEnter", "FileType", "ModeChanged", "WinEnter" }, {
	group = vim.api.nvim_create_augroup("dotfiles-cursorline-mode", { clear = true }),
	callback = schedule_current_mode_ui,
})

vim.api.nvim_create_autocmd("CmdlineEnter", {
	group = vim.api.nvim_create_augroup("dotfiles-cursorline-command", { clear = true }),
	callback = function()
		local win = vim.api.nvim_get_current_win()
		apply_mode_ui(win, "command")
		-- The editing grid is otherwise left with its pre-command-line colors.
		vim.cmd.redraw({ bang = true })
	end,
})

vim.api.nvim_create_autocmd("CmdlineLeave", {
	group = "dotfiles-cursorline-command",
	callback = function()
		local win = vim.api.nvim_get_current_win()
		vim.schedule(function()
			local scene = win == vim.api.nvim_get_current_win() and current_mode_scene() or "default"
			apply_mode_ui(win, scene)
		end)
	end,
})

vim.api.nvim_create_autocmd("WinClosed", {
	group = "dotfiles-cursorline-mode",
	callback = function(args)
		window_scenes[tonumber(args.match)] = nil
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
