local catppuccin = require("config.catppuccin")
local colors = catppuccin.palette()

local function dashboard_square()
	return {
		{ " ▀ █ █ ▀ ", hl = "SnacksDashboardSquareRed" },
		{ " ▀ █ █ ▀ ", hl = "SnacksDashboardSquareGreen" },
		{ " ▀ █ █ ▀ ", hl = "SnacksDashboardSquareYellow" },
		{ " ▀ █ █ ▀ ", hl = "SnacksDashboardSquareBlue" },
		{ " ▀ █ █ ▀ ", hl = "SnacksDashboardSquareMagenta" },
		{ " ▀ █ █ ▀ \n", hl = "SnacksDashboardSquareCyan" },
		{ " ██   ██ ", hl = "SnacksDashboardSquareRed" },
		{ " ██   ██ ", hl = "SnacksDashboardSquareGreen" },
		{ " ██   ██ ", hl = "SnacksDashboardSquareYellow" },
		{ " ██   ██ ", hl = "SnacksDashboardSquareBlue" },
		{ " ██   ██ ", hl = "SnacksDashboardSquareMagenta" },
		{ " ██   ██ \n", hl = "SnacksDashboardSquareCyan" },
		{ " ▄ █ █ ▄ ", hl = "SnacksDashboardSquareRed" },
		{ " ▄ █ █ ▄ ", hl = "SnacksDashboardSquareGreen" },
		{ " ▄ █ █ ▄ ", hl = "SnacksDashboardSquareYellow" },
		{ " ▄ █ █ ▄ ", hl = "SnacksDashboardSquareBlue" },
		{ " ▄ █ █ ▄ ", hl = "SnacksDashboardSquareMagenta" },
		{ " ▄ █ █ ▄ ", hl = "SnacksDashboardSquareCyan" },
	}
end

local function dashboard_spacers(count)
	local lines = {}
	for _ = 1, count do
		lines[#lines + 1] = {
			text = {
				{ "", width = 60 },
			},
		}
	end
	return lines
end

local function dashboard_actions()
	return function(self)
		local items = vim.deepcopy(self.opts.preset.keys)
		for _, item in ipairs(items) do
			item.indent = 2
		end

		local actions = {
			{
				icon = " ",
				title = "Actions",
				padding = { 1, 0 },
			},
		}
		vim.list_extend(actions, items)
		return actions
	end
end

local function set_dashboard_highlights()
	vim.api.nvim_set_hl(0, "SnacksDashboardHeader", { fg = colors.blue, bold = true })
	vim.api.nvim_set_hl(0, "SnacksDashboardKey", { fg = colors.yellow, bold = true })
	vim.api.nvim_set_hl(0, "SnacksDashboardDesc", { fg = colors.text })
	vim.api.nvim_set_hl(0, "SnacksDashboardIcon", { fg = colors.teal })
	vim.api.nvim_set_hl(0, "SnacksDashboardTitle", { fg = colors.mauve, bold = true })
	vim.api.nvim_set_hl(0, "SnacksDashboardFile", { fg = colors.text })
	vim.api.nvim_set_hl(0, "SnacksDashboardDir", { fg = colors.overlay1 })
	vim.api.nvim_set_hl(0, "SnacksDashboardFooter", { fg = colors.overlay1, italic = true })
	vim.api.nvim_set_hl(0, "SnacksDashboardSpecial", { fg = colors.sky })
	vim.api.nvim_set_hl(0, "SnacksDashboardSquareRed", { fg = colors.red, bold = true })
	vim.api.nvim_set_hl(0, "SnacksDashboardSquareGreen", { fg = colors.green, bold = true })
	vim.api.nvim_set_hl(0, "SnacksDashboardSquareYellow", { fg = colors.yellow, bold = true })
	vim.api.nvim_set_hl(0, "SnacksDashboardSquareBlue", { fg = colors.blue, bold = true })
	vim.api.nvim_set_hl(0, "SnacksDashboardSquareMagenta", { fg = colors.mauve, bold = true })
	vim.api.nvim_set_hl(0, "SnacksDashboardSquareCyan", { fg = colors.teal, bold = true })
end

return {
	{
		"catppuccin/nvim",
		name = "catppuccin",
		priority = 1000,
		lazy = false,
		opts = {
			flavour = catppuccin.flavour,
			transparent_background = true,
			float = {
				transparent = true,
				solid = false,
			},
			term_colors = true,
			auto_integrations = true,
			integrations = {
				snacks = {
					enabled = true,
					indent_scope_color = "overlay2",
				},
			},
		},
		config = function(_, opts)
			require("catppuccin").setup(opts)
			vim.cmd.colorscheme(catppuccin.colorscheme())
		end,
	},
	{
		"folke/snacks.nvim",
		priority = 900,
		lazy = false,
		dependencies = { "nvim-tree/nvim-web-devicons" },
		opts = {
			bigfile = { enabled = true },
			git = { enabled = true },
			notifier = { enabled = true, timeout = 3000 },
			quickfile = { enabled = true },
			dashboard = {
				enabled = true,
				width = 60,
				pane_gap = 8,
				preset = {
					pick = function(cmd, opts)
						local fzf = require("fzf-lua")

						if cmd == "files" then
							fzf.files(opts)
						elseif cmd == "live_grep" then
							fzf.live_grep(opts)
						elseif cmd == "oldfiles" then
							fzf.oldfiles(opts)
						end
					end,
					header = [[
███╗   ██╗███████╗ ██████╗ ██╗   ██╗██╗███╗   ███╗
████╗  ██║██╔════╝██╔═══██╗██║   ██║██║████╗ ████║
██╔██╗ ██║█████╗  ██║   ██║██║   ██║██║██╔████╔██║
██║╚██╗██║██╔══╝  ██║   ██║╚██╗ ██╔╝██║██║╚██╔╝██║
██║ ╚████║███████╗╚██████╔╝ ╚████╔╝ ██║██║ ╚═╝ ██║
╚═╝  ╚═══╝╚══════╝ ╚═════╝   ╚═══╝  ╚═╝╚═╝     ╚═╝
					]],
					keys = {
						{
							icon = " ",
							key = "f",
							desc = "Find File",
							action = ":lua Snacks.dashboard.pick('files')",
						},
						{ icon = " ", key = "n", desc = "New File", action = ":ene | startinsert" },
						{
							icon = "󰱼 ",
							key = "g",
							desc = "Find Text",
							action = ":lua Snacks.dashboard.pick('live_grep')",
						},
						{
							icon = " ",
							key = "r",
							desc = "Recent Files",
							action = ":lua Snacks.dashboard.pick('oldfiles')",
						},
						{
							icon = " ",
							key = "c",
							desc = "Config",
							action = ":lua Snacks.dashboard.pick('files', { cwd = vim.fn.stdpath('config') })",
						},
						{
							icon = "󰒲 ",
							key = "l",
							desc = "Lazy",
							action = ":Lazy",
							enabled = package.loaded.lazy ~= nil,
						},
						{ icon = " ", key = "q", desc = "Quit", action = ":qa" },
					},
				},
				formats = {
					key = function(item)
						return {
							{ "[", hl = "SnacksDashboardSpecial" },
							{ item.key, hl = "SnacksDashboardKey" },
							{ "]", hl = "SnacksDashboardSpecial" },
						}
					end,
				},
				sections = {
					{ section = "header" },
					dashboard_actions(),
					{
						pane = 2,
						text = dashboard_square(),
						padding = { 5, 1 },
					},
					{
						pane = 2,
						icon = " ",
						title = "Recent Files",
						section = "recent_files",
						indent = 2,
						padding = { 1, 1 },
						limit = 5,
					},
					{
						pane = 2,
						icon = " ",
						title = "Projects",
						section = "projects",
						indent = 2,
						padding = { 1, 1 },
						limit = 5,
					},
					dashboard_spacers(5),
					{ section = "startup" },
				},
			},
		},
		init = function()
			vim.api.nvim_create_autocmd("ColorScheme", {
				pattern = "*",
				callback = set_dashboard_highlights,
			})
			set_dashboard_highlights()
		end,
	},
}
