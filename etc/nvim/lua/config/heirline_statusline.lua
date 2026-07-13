local M = {}

local conditions = require("heirline.conditions")
local uv = vim.uv or vim.loop

-- Repo-wide diff stats are too expensive to recompute on every statusline
-- redraw, so keep a short-lived cache and refresh it asynchronously.
local git_status_cache = {}
local git_status_ttl_ms = 1500

local function get_palette()
	return require("catppuccin.palettes").get_palette()
end

local function get_settings()
	local colors = get_palette()
	local settings = {
		text = colors.mantle,
		bkg = colors.crust,
		git_branch = colors.mauve,
		git_diff = colors.surface0,
		extras = colors.overlay1,
		curr_file = colors.maroon,
		curr_dir = colors.flamingo,
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

local function current_git_root()
	local gst = vim.b.gitsigns_status_dict
	if gst and gst.root and gst.root ~= "" then
		return gst.root
	end

	local bufname = vim.api.nvim_buf_get_name(0)
	local start = bufname ~= "" and vim.fs.dirname(bufname) or vim.fn.getcwd()
	local gitdir = vim.fs.find(".git", { path = start, upward = true })[1]
	if gitdir then
		return vim.fs.dirname(gitdir)
	end
end

local function parse_git_numstat(output)
	local status = { changed = 0, added = 0, removed = 0 }

	for line in output:gmatch("[^\r\n]+") do
		local added, removed = line:match("^(%d+)%s+(%d+)%s+")
		if added and removed then
			status.changed = status.changed + 1
			status.added = status.added + tonumber(added)
			status.removed = status.removed + tonumber(removed)
		elseif line:match("^%-%s+%-%s+") then
			status.changed = status.changed + 1
		end
	end

	return status
end

local function run_git_repo_status(root)
	local cmd = { "git", "diff", "--numstat", "HEAD", "--" }
	local result = vim.system(cmd, { cwd = root, text = true }):wait()
	if result.code == 0 then
		return parse_git_numstat(result.stdout or "")
	end

	return { changed = 0, added = 0, removed = 0 }
end

local function refresh_git_repo_status(root, sync)
	if not root then
		return { changed = 0, added = 0, removed = 0 }
	end

	local cmd = { "git", "diff", "--numstat", "HEAD", "--" }
	local cached = git_status_cache[root]
	if sync then
		local status = run_git_repo_status(root)
		git_status_cache[root] = {
			status = status,
			at = uv.now(),
			refreshing = false,
		}
		return status
	end

	if cached and cached.refreshing then
		return cached.status
	end

	git_status_cache[root] = {
		status = cached and cached.status or { changed = 0, added = 0, removed = 0 },
		at = cached and cached.at or 0,
		refreshing = true,
	}

	vim.system(cmd, { cwd = root, text = true }, function(result)
		local status = result.code == 0 and parse_git_numstat(result.stdout or "")
			or { changed = 0, added = 0, removed = 0 }
		git_status_cache[root] = {
			status = status,
			at = uv.now(),
			refreshing = false,
		}

		vim.schedule(function()
			vim.cmd("redrawstatus")
		end)
	end)

	return git_status_cache[root].status
end

local function repo_git_status()
	local root = current_git_root()
	if not root then
		return { changed = 0, added = 0, removed = 0 }
	end

	local cached = git_status_cache[root]
	local now = uv.now()
	if not cached then
		return refresh_git_repo_status(root, true)
	end

	if now - cached.at > git_status_ttl_ms then
		return refresh_git_repo_status(root, false)
	end

	return cached.status
end

local function any_git_changes()
	local status = repo_git_status()
	return status.added > 0 or status.changed > 0 or status.removed > 0
end

local function in_git_repo()
	return vim.b.gitsigns_head ~= nil and vim.b.gitsigns_head ~= ""
end

local function git_count(key)
	local status = repo_git_status()
	if not status[key] or status[key] <= 0 then
		return nil
	end

	return status[key]
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
	if not vim.lsp.status or not vim.lsp.util or not vim.lsp.util.get_progress_messages then
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

local function lsp_chip_text()
	local parts = { lsp_name() }
	local severities = {
		{ vim.diagnostic.severity.ERROR, "󰅚", "DotfilesDiagnosticError" },
		{ vim.diagnostic.severity.WARN, "󰀪", "DotfilesDiagnosticWarn" },
		{ vim.diagnostic.severity.INFO, "", "DotfilesDiagnosticInfo" },
		{ vim.diagnostic.severity.HINT, "󰌵", "DotfilesDiagnosticHint" },
	}

	for _, item in ipairs(severities) do
		local count = diagnostic_count(item[1])
		if count > 0 then
			parts[#parts + 1] = string.format("%%#%s#%s %d%%#DotfilesLspChip#", item[3], item[2], count)
		end
	end

	return "%#DotfilesLspChip# " .. table.concat(parts, "  ") .. " "
end

local function file_name()
	local filename = vim.fn.expand("%:t")
	local extension = vim.fn.expand("%:e")
	local filetype = vim.bo.filetype
	if filetype == "" then
		filetype = vim.filetype.match({ filename = vim.api.nvim_buf_get_name(0) }) or ""
	end
	local ok, icons = pcall(require, "nvim-web-devicons")
	local icon = ok and icons.get_icon(filename, extension) or nil
	local spacing = filetype == "markdown" and "  " or " "

	return " " .. (icon or "󰈙") .. spacing .. filename .. " "
end

local function current_dir()
	return " 󰉖 " .. vim.fn.fnamemodify(vim.fn.getcwd(), ":t") .. " "
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
			return not in_git_repo()
		end,
		hl = function()
			local settings = get_settings()
			local mode = current_mode()
			return { fg = mode[2], bg = settings.bkg }
		end,
	},
	{
		provider = "",
		condition = in_git_repo,
		hl = function()
			local settings = get_settings()
			local mode = current_mode()
			return { fg = mode[2], bg = settings.git_branch }
		end,
	},
}

local function GitStatusComponent(provider, opts)
	opts = opts or {}
	return {
		condition = opts.condition,
		provider = function()
			return provider()
		end,
		hl = function()
			local settings = get_settings()
			return vim.tbl_extend("force", { fg = settings.text, bg = settings.git_diff }, opts.hl and opts.hl() or {})
		end,
	}
end

local GitBranch = {
	condition = in_git_repo,
	{
		provider = function()
			return "  " .. vim.b.gitsigns_head
		end,
		hl = function()
			local settings = get_settings()
			return { fg = settings.text, bg = settings.git_branch, bold = true }
		end,
	},
	{
		provider = "",
		condition = function()
			return any_git_changes()
		end,
		hl = function()
			local settings = get_settings()
			return { fg = settings.git_branch, bg = settings.git_diff }
		end,
	},
	{
		provider = "",
		condition = function()
			return not any_git_changes()
		end,
		hl = function()
			local settings = get_settings()
			return { fg = settings.git_branch, bg = settings.bkg }
		end,
	},
}

local GitDiff = {
	condition = any_git_changes,
	GitStatusComponent(function()
		return " +" .. git_count("added")
	end, {
		condition = function()
			return git_count("added") ~= nil
		end,
		hl = function()
			return { fg = get_palette().green, bold = true }
		end,
	}),
	GitStatusComponent(function()
		return " ~" .. git_count("changed")
	end, {
		condition = function()
			return git_count("changed") ~= nil
		end,
		hl = function()
			return { fg = get_palette().yellow, bold = true }
		end,
	}),
	GitStatusComponent(function()
		return " -" .. git_count("removed")
	end, {
		condition = function()
			return git_count("removed") ~= nil
		end,
		hl = function()
			return { fg = get_palette().red, bold = true }
		end,
	}),
	{
		provider = " ",
		hl = function()
			local settings = get_settings()
			return { fg = settings.bkg, bg = settings.git_diff }
		end,
	},
	{
		provider = "",
		hl = function()
			local settings = get_settings()
			return { fg = settings.git_diff, bg = settings.bkg }
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

local LspChip = {
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
			return lsp_name() ~= ""
		end,
		provider = "",
		hl = function()
			local settings = get_settings()
			return { fg = settings.git_diff, bg = settings.bkg }
		end,
	},
	{
		condition = function()
			return lsp_name() ~= ""
		end,
		provider = lsp_chip_text,
		hl = function()
			local colors = get_palette()
			local settings = get_settings()
			return { fg = colors.text, bg = settings.git_diff, bold = true }
		end,
	},
	init = function(self)
		local settings = get_settings()
		local colors = get_palette()
		vim.api.nvim_set_hl(0, "DotfilesLspChip", { fg = colors.text, bg = settings.git_diff, bold = true })
		vim.api.nvim_set_hl(0, "DotfilesDiagnosticError", { fg = colors.red, bg = settings.git_diff, bold = true })
		vim.api.nvim_set_hl(0, "DotfilesDiagnosticWarn", { fg = colors.yellow, bg = settings.git_diff, bold = true })
		vim.api.nvim_set_hl(0, "DotfilesDiagnosticInfo", { fg = colors.sky, bg = settings.git_diff, bold = true })
		vim.api.nvim_set_hl(0, "DotfilesDiagnosticHint", { fg = colors.rosewater, bg = settings.git_diff, bold = true })
	end,
}

local RightSection = {
	LspChip,
	{
		condition = function()
			return width_above(70)
		end,
		provider = "",
		hl = function()
			local settings = get_settings()
			local bg = lsp_name() ~= "" and settings.git_diff or settings.bkg
			return { fg = settings.curr_file, bg = bg }
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

local ActiveStatusline = {
	ViMode,
	GitBranch,
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
	})
end

return M
