local M = {}

local height = 15
local commits_ratio = 0.7
local views = {
	files = {
		cmd = { "lazygit", "status", "--screen-mode", "full" },
		label = "Files",
	},
	commits = {
		cmd = { "lazygit", "log", "--screen-mode", "full" },
		label = "Commits",
	},
}
local state = {
	groups = {},
	augroup = nil,
	resize_generation = 0,
}

local function append_config(config_files, config_file)
	for candidate in config_files:gmatch("[^,]+") do
		if candidate == config_file then
			return config_files
		end
	end
	return config_files == "" and config_file or (config_files .. "," .. config_file)
end

function M.env(extra_configs)
	local config_home = vim.env.XDG_CONFIG_HOME or vim.fs.joinpath(vim.env.HOME, ".config")
	local config_files = vim.env.LG_CONFIG_FILE or ""
	config_files = append_config(config_files, vim.fs.joinpath(config_home, "herdr", "lazygit-unified.yml"))

	for _, config_file in ipairs(extra_configs or {}) do
		config_files = append_config(config_files, config_file)
	end

	return { LG_CONFIG_FILE = config_files }
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

local function valid(terminal)
	return terminal and terminal.buf and vim.api.nvim_buf_is_valid(terminal.buf)
end

local function visible(terminal, tabpage)
	return valid(terminal)
		and terminal:valid()
		and vim.api.nvim_win_get_tabpage(terminal.win) == (tabpage or vim.api.nvim_get_current_tabpage())
end

local function group_visible(group)
	return visible(group.files, group.tabpage) or visible(group.commits, group.tabpage)
end

local function group_window(group, win)
	return (visible(group.files, group.tabpage) and group.files.win == win)
		or (visible(group.commits, group.tabpage) and group.commits.win == win)
end

local function window_options(label, placement)
	return {
		position = placement.position,
		relative = placement.relative,
		win = placement.win,
		height = height,
		width = placement.width,
		stack = false,
		enter = true,
		keys = pane_keys(),
		wo = {
			winbar = "   " .. label,
			winfixheight = true,
			winfixwidth = false,
		},
	}
end

local function graph_config()
	local config_home = vim.env.XDG_CONFIG_HOME or vim.fs.joinpath(vim.env.HOME, ".config")
	return vim.fs.joinpath(config_home, "lazygit", "nvim-files-commits.yml")
end

local function terminal_options(group, view, placement)
	return {
		count = group.tabpage,
		cwd = group.cwd,
		env = M.env(view == "commits" and { graph_config() } or nil),
		win = window_options(views[view].label, placement),
	}
end

local function apply_window_options(terminal, opts)
	for key, value in pairs(opts) do
		terminal.opts[key] = value
	end
end

local function remember_fixed_heights(group)
	group.fixed_heights = {}
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(group.tabpage)) do
		local buf = vim.api.nvim_win_get_buf(win)
		if vim.wo[win].winfixheight or vim.bo[buf].filetype == "trouble" or vim.bo[buf].buftype == "quickfix" then
			group.fixed_heights[win] = vim.api.nvim_win_get_height(win)
		end
	end
end

local function restore_fixed_heights(group)
	local fixed_windows = {}
	for win, height in pairs(group.fixed_heights or {}) do
		if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_tabpage(win) == group.tabpage then
			fixed_windows[#fixed_windows + 1] = { win = win, height = height }
		end
	end
	table.sort(fixed_windows, function(left, right)
		local left_row = vim.api.nvim_win_get_position(left.win)[1]
		local right_row = vim.api.nvim_win_get_position(right.win)[1]
		if left_row == right_row then
			return left.win < right.win
		end
		return left_row > right_row
	end)
	for _, fixed in ipairs(fixed_windows) do
		if vim.api.nvim_win_is_valid(fixed.win) and vim.api.nvim_win_get_tabpage(fixed.win) == group.tabpage then
			vim.api.nvim_win_set_height(fixed.win, fixed.height)
		end
	end
end

local function enforce_layout(group)
	group.layout_generation = (group.layout_generation or 0) + 1
	local generation = group.layout_generation

	local function current_group()
		return group.layout_generation == generation
			and state.groups[group.tabpage] == group
			and not group.closing
			and visible(group.files, group.tabpage)
			and visible(group.commits, group.tabpage)
	end

	local function resize()
		if not current_group() then
			return
		end

		vim.api.nvim_win_set_height(group.files.win, height)
		vim.api.nvim_win_set_height(group.commits.win, height)
		vim.wo[group.files.win].winfixheight = true
		vim.wo[group.commits.win].winfixheight = true
		local total_width = vim.api.nvim_win_get_width(group.commits.win) + vim.api.nvim_win_get_width(group.files.win)
		local commits_width = math.max(20, math.floor(total_width * commits_ratio + 0.5))
		commits_width = math.min(commits_width, math.max(20, total_width - 20))
		if vim.api.nvim_win_get_width(group.commits.win) ~= commits_width then
			vim.api.nvim_win_set_width(group.commits.win, commits_width)
		end
	end

	resize()
	vim.schedule(function()
		if not current_group() then
			return
		end
		resize()
		if not current_group() then
			return
		end
		restore_fixed_heights(group)
		if not current_group() then
			return
		end
		local sidebar = package.loaded["config.sidebar"]
		if sidebar and type(sidebar.sync) == "function" then
			sidebar.sync(group.tabpage)
		end
	end)
end

local function focus_commits(group)
	if visible(group.commits, group.tabpage) then
		group.commits:focus()
	end
end

local close_group

local function register_lifecycle(group, terminal)
	vim.api.nvim_create_autocmd("TermClose", {
		group = state.augroup,
		buffer = terminal.buf,
		once = true,
		callback = function()
			vim.schedule(function()
				if not group.closing then
					close_group(group)
				end
			end)
		end,
	})
end

close_group = function(group)
	if not group or group.closing then
		return
	end
	group.closing = true
	if state.groups[group.tabpage] == group then
		state.groups[group.tabpage] = nil
	end

	for _, terminal in ipairs({ group.commits, group.files }) do
		if valid(terminal) then
			pcall(function()
				terminal:close()
			end)
		end
	end
	restore_fixed_heights(group)
end

local function setup()
	if state.augroup then
		return
	end

	state.augroup = vim.api.nvim_create_augroup("dotfiles-lazygit-panes", { clear = true })
	vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
		group = state.augroup,
		callback = function()
			state.resize_generation = state.resize_generation + 1
			local generation = state.resize_generation
			vim.defer_fn(function()
				if generation ~= state.resize_generation then
					return
				end
				for _, group in pairs(state.groups) do
					enforce_layout(group)
				end
			end, 30)
		end,
	})
end

local function commits_placement()
	local terminal_win = bottom_terminal_window()
	return {
		position = terminal_win and "top" or "bottom",
		relative = terminal_win and "win" or "editor",
		win = terminal_win,
	}
end

local function files_placement(commits_win)
	return {
		position = "right",
		relative = "win",
		win = commits_win,
		width = 1 - commits_ratio,
	}
end

local function create_group(cwd, return_win)
	local snacks = require("snacks")
	local group = {
		tabpage = vim.api.nvim_get_current_tabpage(),
		cwd = cwd,
		return_win = return_win,
	}
	remember_fixed_heights(group)
	state.groups[group.tabpage] = group

	local ok, err = pcall(function()
		group.commits = snacks.terminal.open(views.commits.cmd, terminal_options(group, "commits", commits_placement()))
		group.files =
			snacks.terminal.open(views.files.cmd, terminal_options(group, "files", files_placement(group.commits.win)))
	end)
	if not ok then
		close_group(group)
		error(err)
	end

	register_lifecycle(group, group.files)
	register_lifecycle(group, group.commits)
	enforce_layout(group)
	focus_commits(group)
	return group
end

local function show_group(group, return_win)
	group.return_win = return_win
	remember_fixed_heights(group)
	apply_window_options(group.commits, window_options(views.commits.label, commits_placement()))
	group.commits:show()
	apply_window_options(group.files, window_options(views.files.label, files_placement(group.commits.win)))
	group.files:show()
	enforce_layout(group)
	focus_commits(group)
	return group
end

local function hide_group(group)
	local current = vim.api.nvim_get_current_win()
	if not group_window(group, current) then
		group.return_win = current
	end

	if visible(group.files, group.tabpage) then
		group.files:hide()
	end
	if visible(group.commits, group.tabpage) then
		group.commits:hide()
	end
	restore_fixed_heights(group)
	if
		group.return_win
		and vim.api.nvim_win_is_valid(group.return_win)
		and vim.api.nvim_win_get_tabpage(group.return_win) == group.tabpage
	then
		vim.api.nvim_set_current_win(group.return_win)
	end
	return group
end

function M.toggle()
	setup()
	local tabpage = vim.api.nvim_get_current_tabpage()
	local current_win = vim.api.nvim_get_current_win()
	local cwd = vim.fn.getcwd(0)
	local group = state.groups[tabpage]

	if group and group_visible(group) then
		return hide_group(group)
	end
	if group and group.cwd == cwd and valid(group.files) and valid(group.commits) then
		return show_group(group, current_win)
	end
	if group then
		close_group(group)
	end
	return create_group(cwd, current_win)
end

function M.close_all()
	local groups = {}
	for _, group in pairs(state.groups) do
		groups[#groups + 1] = group
	end
	for _, group in ipairs(groups) do
		close_group(group)
	end
end

return M
