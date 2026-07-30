local M = {}

local command = { "lazygit" }
local height = 15

function M.env()
	local config_home = vim.env.XDG_CONFIG_HOME or vim.fs.joinpath(vim.env.HOME, ".config")
	local unified_config = vim.fs.joinpath(config_home, "herdr", "lazygit-unified.yml")
	local config_files = vim.env.LG_CONFIG_FILE or ""

	for config_file in config_files:gmatch("[^,]+") do
		if config_file == unified_config then
			return { LG_CONFIG_FILE = config_files }
		end
	end

	return {
		LG_CONFIG_FILE = config_files == "" and unified_config or (config_files .. "," .. unified_config),
	}
end

local function bottom_terminal_window()
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if vim.w[win].dotfiles_terminal_group then
			return win
		end
	end
end

local function move_to_pane(direction)
	local current = vim.api.nvim_get_current_win()
	local target = vim.fn.win_getid(vim.fn.winnr(direction))
	if target == 0 or target == current then
		return
	end

	vim.cmd.stopinsert()
	vim.api.nvim_set_current_win(target)
	if vim.bo[vim.api.nvim_win_get_buf(target)].buftype == "terminal" then
		vim.schedule(function()
			if vim.api.nvim_win_is_valid(target) and vim.api.nvim_get_current_win() == target then
				vim.cmd.startinsert()
			end
		end)
	end
end

local function pane_keys()
	local keys = {}
	for direction, name in pairs({ h = "left", j = "lower", k = "upper", l = "right" }) do
		keys["pane_" .. name] = {
			"<C-w>" .. direction,
			function()
				move_to_pane(direction)
			end,
			mode = "t",
			nowait = true,
			desc = "Move to " .. name .. " pane",
		}
	end
	return keys
end

local function window_options()
	local terminal_win = bottom_terminal_window()
	return {
		position = terminal_win and "top" or "bottom",
		relative = terminal_win and "win" or "editor",
		win = terminal_win,
		height = height,
		stack = false,
		enter = true,
		keys = pane_keys(),
		wo = {
			winbar = "   lazygit",
			winfixheight = true,
		},
	}
end

local function terminal_options(create)
	return {
		count = vim.api.nvim_get_current_tabpage(),
		cwd = vim.fn.getcwd(0),
		env = M.env(),
		create = create,
		win = window_options(),
	}
end

local function apply_window_options(terminal, opts)
	for key, value in pairs(opts) do
		terminal.opts[key] = value
	end
end

local function enforce_height(terminal)
	local function resize()
		if terminal:valid() then
			vim.api.nvim_win_set_height(terminal.win, height)
		end
	end

	resize()
	vim.schedule(resize)
end

function M.toggle()
	local snacks = require("snacks")
	local lookup = terminal_options(false)
	local terminal = snacks.terminal.get(command, lookup)

	if not terminal then
		lookup.create = nil
		terminal = snacks.terminal.open(command, lookup)
		enforce_height(terminal)
		return terminal
	end

	if terminal:valid() and vim.api.nvim_win_get_tabpage(terminal.win) == vim.api.nvim_get_current_tabpage() then
		terminal:hide()
		return terminal
	end

	if terminal:valid() then
		terminal:hide()
	end
	apply_window_options(terminal, lookup.win)
	terminal:show()
	enforce_height(terminal)
	terminal:focus()
	return terminal
end

return M
