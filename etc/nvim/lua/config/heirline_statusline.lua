local M = {}

local conditions = require("heirline.conditions")
local utils = require("heirline.utils")

local function get_palette()
	return require("catppuccin.palettes").get_palette()
end

local function get_settings()
	local colors = get_palette()
	local settings = {
		text = colors.mantle,
		bkg = colors.crust,
		diffs = colors.mauve,
		extras = colors.overlay1,
		curr_file = colors.maroon,
		curr_dir = colors.flamingo,
		tab_active = colors.surface0,
		tab_inactive = colors.mantle,
		tab_text_active = colors.text,
		tab_text_inactive = colors.subtext1,
		tab_accent = colors.blue,
		tab_muted = colors.overlay1,
		tab_modified = colors.peach,
		tab_count = colors.teal,
	}

	if require("catppuccin").flavour == "latte" then
		local latte = require("catppuccin.palettes").get_palette("latte")
		settings.text = latte.base
		settings.bkg = latte.crust
	end

	if require("catppuccin").options.transparent_background then
		settings.bkg = "NONE"
	end

	return settings
end

local function mode_colors()
	local colors = get_palette()
	return {
		["n"] = { "NORMAL", colors.lavender },
		["no"] = { "N-PENDING", colors.lavender },
		["i"] = { "INSERT", colors.green },
		["ic"] = { "INSERT", colors.green },
		["t"] = { "TERMINAL", colors.green },
		["v"] = { "VISUAL", colors.flamingo },
		["V"] = { "V-LINE", colors.flamingo },
		["\22"] = { "V-BLOCK", colors.flamingo },
		["R"] = { "REPLACE", colors.maroon },
		["Rv"] = { "V-REPLACE", colors.maroon },
		["s"] = { "SELECT", colors.maroon },
		["S"] = { "S-LINE", colors.maroon },
		["\19"] = { "S-BLOCK", colors.maroon },
		["c"] = { "COMMAND", colors.peach },
		["cv"] = { "COMMAND", colors.peach },
		["ce"] = { "COMMAND", colors.peach },
		["r"] = { "PROMPT", colors.teal },
		["rm"] = { "MORE", colors.teal },
		["r?"] = { "CONFIRM", colors.mauve },
		["!"] = { "SHELL", colors.green },
	}
end

local function current_mode()
	local modes = mode_colors()
	return modes[vim.fn.mode(1)] or modes[vim.fn.mode()] or modes.n
end

local function any_git_changes()
	local gst = vim.b.gitsigns_status_dict
	return gst
		and ((gst.added and gst.added > 0) or (gst.removed and gst.removed > 0) or (gst.changed and gst.changed > 0))
end

local function width_above(min_width)
	return vim.api.nvim_win_get_width(0) > min_width
end

local function cmdheight_zero()
	return vim.api.nvim_get_option_value("cmdheight", { scope = "global" }) == 0
end

local function diagnostic_count(severity)
	return #vim.diagnostic.get(0, { severity = severity })
end

local function lsp_progress()
	if vim.lsp.status then
		return ""
	end

	local progress = vim.lsp.util.get_progress_messages()[1]
	if not progress then
		return ""
	end

	local message = progress.message or ""
	local percentage = progress.percentage
	if not percentage then
		return ""
	end

	local title = progress.title or ""
	local spinners = { "", "󰀚", "" }
	local success_icon = { "", "", "" }
	local ms = vim.loop.hrtime() / 1000000
	local frame = math.floor(ms / 120) % #spinners + 1

	if percentage >= 70 then
		return string.format(" %%<%s %s %s (%s%%%%) ", success_icon[frame], title, message, percentage)
	end

	return string.format(" %%<%s %s %s (%s%%%%) ", spinners[frame], title, message, percentage)
end

local function lsp_name()
	local active_clients = vim.lsp.get_clients({ bufnr = 0 })
	if next(active_clients) == nil then
		return ""
	end

	return "󰅡 Lsp"
end

local function file_name()
	local filename = vim.fn.expand("%:t")
	local extension = vim.fn.expand("%:e")
	local ok, icons = pcall(require, "nvim-web-devicons")
	local icon = ok and icons.get_icon(filename, extension) or nil

	return " " .. (icon or "󰈙") .. " " .. filename .. " "
end

local function current_dir()
	return " 󰉖 " .. vim.fn.fnamemodify(vim.fn.getcwd(), ":t") .. " "
end

local function tabpage_bufnr(tabpage)
	local win = vim.api.nvim_tabpage_get_win(tabpage)
	return vim.api.nvim_win_get_buf(win)
end

local function tabpage_name(tabpage)
	local bufnr = tabpage_bufnr(tabpage)
	local name = vim.api.nvim_buf_get_name(bufnr)

	if name == "" then
		local filetype = vim.bo[bufnr].filetype
		if filetype ~= "" then
			return "[" .. filetype .. "]"
		end

		return "[No Name]"
	end

	return vim.fn.fnamemodify(name, ":t")
end

local function tabpage_icon(tabpage)
	local filename = tabpage_name(tabpage)
	local extension = vim.fn.fnamemodify(filename, ":e")
	local ok, icons = pcall(require, "nvim-web-devicons")
	if not ok then
		return "󰈙"
	end

	return icons.get_icon(filename, extension, { default = true }) or "󰈙"
end

local function tabpage_modified(tabpage)
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
		local bufnr = vim.api.nvim_win_get_buf(win)
		if vim.bo[bufnr].modified then
			return true
		end
	end

	return false
end

local function file_progress()
	local current_line = vim.fn.line(".")
	local total_line = vim.fn.line("$")

	if current_line == 1 then
		return "Top"
	elseif current_line == total_line then
		return "Bot"
	end

	local result = math.modf((current_line / total_line) * 100)
	return result .. "%%"
end

local function position()
	local line, col = unpack(vim.api.nvim_win_get_cursor(0))
	local line_text = vim.api.nvim_get_current_line()
	local before_cursor = line_text:sub(1, col):gsub("\t", string.rep(" ", vim.bo.tabstop))

	col = vim.str_utfindex(before_cursor) + 1
	return string.format("%s:%s", line, col)
end

local function search_count()
	if vim.v.hlsearch == 0 then
		return ""
	end

	local result = vim.fn.searchcount({ maxcount = 999, timeout = 250 })
	if result.incomplete == 1 or next(result) == nil then
		return ""
	end

	return string.format("[%d/%d]", result.current, math.min(result.total, result.maxcount))
end

local function macro_recording()
	local recording_register = vim.fn.reg_recording()
	if recording_register == "" then
		return ""
	end

	return "Recording @" .. recording_register
end

local Space = { provider = " " }
local Align = { provider = "%=" }

local ViMode = {
	{
		provider = "  ",
		hl = function()
			local settings = get_settings()
			local mode = current_mode()
			return { fg = settings.text, bg = mode[2] }
		end,
	},
	{
		provider = function()
			return current_mode()[1] .. " "
		end,
		hl = function()
			local settings = get_settings()
			local mode = current_mode()
			return { fg = settings.text, bg = mode[2], bold = true }
		end,
	},
	{
		provider = "",
		condition = function()
			return not any_git_changes()
		end,
		hl = function()
			local settings = get_settings()
			local mode = current_mode()
			return { fg = mode[2], bg = settings.bkg }
		end,
	},
	{
		provider = "",
		condition = any_git_changes,
		hl = function()
			local settings = get_settings()
			local mode = current_mode()
			return { fg = mode[2], bg = settings.diffs }
		end,
	},
}

local function GitDiffComponent(icon, key)
	return {
		provider = function()
			local gst = vim.b.gitsigns_status_dict
			if not gst or not gst[key] or gst[key] <= 0 then
				return ""
			end
			return " " .. icon .. " " .. gst[key]
		end,
		hl = function()
			local settings = get_settings()
			return { fg = settings.text, bg = settings.diffs }
		end,
	}
end

local GitDiff = {
	condition = any_git_changes,
	GitDiffComponent("", "added"),
	GitDiffComponent("", "changed"),
	GitDiffComponent("", "removed"),
	{
		provider = " ",
		hl = function()
			local settings = get_settings()
			return { fg = settings.bkg, bg = settings.diffs }
		end,
	},
	{
		provider = "",
		hl = function()
			local settings = get_settings()
			return { fg = settings.diffs, bg = settings.bkg }
		end,
	},
}

local function ExtraComponent(provider, condition)
	return {
		condition = condition,
		Space,
		{
			provider = provider,
			hl = function()
				local settings = get_settings()
				return { fg = settings.extras, bg = settings.bkg }
			end,
		},
	}
end

local function RightInfoComponent(provider, condition)
	return {
		condition = condition,
		{
			provider = provider,
			hl = function()
				local settings = get_settings()
				return { fg = settings.extras, bg = settings.bkg }
			end,
		},
		Space,
	}
end

local Diagnostics = {
	{
		condition = function()
			return width_above(80) and lsp_progress() ~= ""
		end,
		provider = lsp_progress,
		hl = function()
			return { fg = get_palette().rosewater, bg = get_settings().bkg }
		end,
	},
	{
		condition = function()
			return diagnostic_count(vim.diagnostic.severity.ERROR) > 0
		end,
		provider = function()
			return "  " .. diagnostic_count(vim.diagnostic.severity.ERROR)
		end,
		hl = function()
			return { fg = get_palette().red, bg = get_settings().bkg }
		end,
	},
	{
		condition = function()
			return diagnostic_count(vim.diagnostic.severity.WARN) > 0
		end,
		provider = function()
			return "  " .. diagnostic_count(vim.diagnostic.severity.WARN)
		end,
		hl = function()
			return { fg = get_palette().yellow, bg = get_settings().bkg }
		end,
	},
	{
		condition = function()
			return diagnostic_count(vim.diagnostic.severity.INFO) > 0
		end,
		provider = function()
			return "  " .. diagnostic_count(vim.diagnostic.severity.INFO)
		end,
		hl = function()
			return { fg = get_palette().sky, bg = get_settings().bkg }
		end,
	},
	{
		condition = function()
			return diagnostic_count(vim.diagnostic.severity.HINT) > 0
		end,
		provider = function()
			return "  " .. diagnostic_count(vim.diagnostic.severity.HINT)
		end,
		hl = function()
			return { fg = get_palette().rosewater, bg = get_settings().bkg }
		end,
	},
}

local RightSection = {
	RightInfoComponent(function()
		return " " .. vim.b.gitsigns_head
	end, function()
		return width_above(70) and vim.b.gitsigns_head ~= nil and vim.b.gitsigns_head ~= ""
	end),
	RightInfoComponent(lsp_name, function()
		return lsp_name() ~= ""
	end),
	{
		condition = function()
			return width_above(70)
		end,
		provider = "",
		hl = function()
			local settings = get_settings()
			return { fg = settings.curr_file, bg = settings.bkg }
		end,
	},
	{
		condition = function()
			return width_above(70)
		end,
		provider = function()
			return file_name()
		end,
		hl = function()
			local settings = get_settings()
			return { fg = settings.text, bg = settings.curr_file }
		end,
	},
	{
		condition = function()
			return width_above(80)
		end,
		provider = "",
		hl = function()
			local settings = get_settings()
			return { fg = settings.curr_dir, bg = settings.curr_file }
		end,
	},
	{
		condition = function()
			return width_above(80)
		end,
		provider = current_dir,
		hl = function()
			local settings = get_settings()
			return { fg = settings.text, bg = settings.curr_dir }
		end,
	},
}

local TabPage = {
	init = function(self)
		self.bufnr = tabpage_bufnr(self.tabpage)
		self.filename = tabpage_name(self.tabpage)
		self.icon = tabpage_icon(self.tabpage)
		self.win_count = #vim.api.nvim_tabpage_list_wins(self.tabpage)
		self.modified = tabpage_modified(self.tabpage)
	end,
	on_click = {
		callback = function(_, minwid, _, button)
			if button == "m" and #vim.api.nvim_list_tabpages() > 1 then
				vim.schedule(function()
					if vim.api.nvim_tabpage_is_valid(minwid) then
						vim.cmd.tabclose(vim.api.nvim_tabpage_get_number(minwid))
					end
				end)
				return
			end

			vim.api.nvim_set_current_tabpage(minwid)
		end,
		minwid = function(self)
			return self.tabpage
		end,
		name = "dotfiles_heirline_tabpage",
	},
	utils.surround({ "", "" }, function(self)
		local settings = get_settings()
		return self.is_active and settings.tab_active or settings.tab_inactive
	end, {
		{
			provider = function(self)
				return " " .. self.tabnr
			end,
			hl = function(self)
				local settings = get_settings()
				local bg = self.is_active and settings.tab_active or settings.tab_inactive
				return {
					fg = self.is_active and settings.tab_accent or settings.tab_muted,
					bg = bg,
					bold = true,
				}
			end,
		},
		{
			provider = function(self)
				return " " .. self.icon
			end,
			hl = function(self)
				local settings = get_settings()
				local bg = self.is_active and settings.tab_active or settings.tab_inactive
				return {
					fg = self.is_active and settings.tab_accent or settings.tab_muted,
					bg = bg,
				}
			end,
		},
		{
			provider = function(self)
				return " " .. self.filename
			end,
			hl = function(self)
				local settings = get_settings()
				local bg = self.is_active and settings.tab_active or settings.tab_inactive
				return {
					fg = self.is_active and settings.tab_text_active or settings.tab_text_inactive,
					bg = bg,
					bold = self.is_active,
				}
			end,
		},
		{
			condition = function(self)
				return self.win_count > 1
			end,
			provider = function(self)
				return " " .. self.win_count .. "w"
			end,
			hl = function(self)
				local settings = get_settings()
				local bg = self.is_active and settings.tab_active or settings.tab_inactive
				return { fg = settings.tab_count, bg = bg }
			end,
		},
		{
			condition = function(self)
				return self.modified
			end,
			provider = " ●",
			hl = function(self)
				local settings = get_settings()
				local bg = self.is_active and settings.tab_active or settings.tab_inactive
				return { fg = settings.tab_modified, bg = bg }
			end,
		},
		{
			condition = function()
				return #vim.api.nvim_list_tabpages() > 1
			end,
			provider = " 󰅖",
			hl = function(self)
				local settings = get_settings()
				local bg = self.is_active and settings.tab_active or settings.tab_inactive
				return {
					fg = self.is_active and settings.tab_modified or settings.tab_muted,
					bg = bg,
				}
			end,
			on_click = {
				callback = function(_, minwid)
					vim.schedule(function()
						if vim.api.nvim_tabpage_is_valid(minwid) then
							vim.cmd.tabclose(vim.api.nvim_tabpage_get_number(minwid))
						end
					end)
				end,
				minwid = function(self)
					return self.tabpage
				end,
				name = "dotfiles_heirline_tabpage_close",
			},
		},
		{
			provider = " ",
			hl = function(self)
				local settings = get_settings()
				return {
					bg = self.is_active and settings.tab_active or settings.tab_inactive,
				}
			end,
		},
	}),
	{ provider = " " },
}

local TabPages = utils.make_tablist(TabPage)

local Tabline = {
	hl = function()
		return { bg = get_settings().bkg }
	end,
	update = { "TabEnter", "TabNew", "TabClosed", "BufEnter", "BufModifiedSet", "WinEnter" },
	{ provider = " " },
	TabPages,
	Align,
}

local ActiveStatusline = {
	ViMode,
	GitDiff,
	ExtraComponent(file_progress),
	ExtraComponent(position),
	ExtraComponent(macro_recording, function()
		return cmdheight_zero() and macro_recording() ~= ""
	end),
	ExtraComponent(search_count, function()
		return cmdheight_zero() and search_count() ~= ""
	end),
	Align,
	Diagnostics,
	Align,
	RightSection,
}

local InactiveStatusline = {
	condition = function()
		return not conditions.is_active()
	end,
	{
		provider = function()
			return " " .. string.upper(vim.bo.filetype) .. " "
		end,
		hl = function()
			local colors = get_palette()
			return { fg = colors.overlay2, bg = colors.mantle }
		end,
	},
}

local Statusline = {
	fallthrough = false,
	{
		condition = conditions.is_active,
		ActiveStatusline,
	},
	InactiveStatusline,
}

function M.setup()
	require("heirline").setup({
		statusline = Statusline,
		tabline = Tabline,
	})
end

return M
