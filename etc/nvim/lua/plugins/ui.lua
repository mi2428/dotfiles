local ghostty = {
	bg = "#1A1F24",
	fg = "#E3E7EA",
	comment = "#78909C",
	red = "#E57373",
	green = "#81C784",
	yellow = "#FFD740",
	blue = "#64B5F6",
	magenta = "#BA68C8",
	cyan = "#4DD0E1",
	white = "#FFFFFF",
}

local function set_dashboard_highlights()
	vim.api.nvim_set_hl(0, "SnacksDashboardHeader", { fg = ghostty.blue, bold = true })
	vim.api.nvim_set_hl(0, "SnacksDashboardKey", { fg = ghostty.yellow, bold = true })
	vim.api.nvim_set_hl(0, "SnacksDashboardDesc", { fg = ghostty.fg })
	vim.api.nvim_set_hl(0, "SnacksDashboardIcon", { fg = ghostty.cyan })
	vim.api.nvim_set_hl(0, "SnacksDashboardTitle", { fg = ghostty.magenta, bold = true })
	vim.api.nvim_set_hl(0, "SnacksDashboardFile", { fg = ghostty.fg })
	vim.api.nvim_set_hl(0, "SnacksDashboardDir", { fg = ghostty.comment })
	vim.api.nvim_set_hl(0, "SnacksDashboardFooter", { fg = ghostty.comment, italic = true })
	vim.api.nvim_set_hl(0, "SnacksDashboardSpecial", { fg = ghostty.cyan })
end

return {
	{
		"folke/tokyonight.nvim",
		priority = 1000,
		lazy = false,
		opts = {
			style = "night",
			transparent = false,
			terminal_colors = true,
			on_colors = function(colors)
				colors.bg = ghostty.bg
				colors.bg_dark = ghostty.bg
				colors.bg_float = ghostty.bg
				colors.bg_sidebar = ghostty.bg
				colors.fg = ghostty.fg
				colors.comment = ghostty.comment
				colors.red = ghostty.red
				colors.green = ghostty.green
				colors.yellow = ghostty.yellow
				colors.blue = ghostty.blue
				colors.magenta = ghostty.magenta
				colors.cyan = ghostty.cyan
			end,
			on_highlights = function(hl, colors)
				hl.Normal = { fg = colors.fg, bg = ghostty.bg }
				hl.NormalNC = { fg = colors.fg, bg = ghostty.bg }
				hl.NormalFloat = { fg = colors.fg, bg = ghostty.bg }
				hl.FloatBorder = { fg = ghostty.comment, bg = ghostty.bg }
				hl.CursorLine = { bg = "#222930" }
				hl.Visual = { bg = "#2A3139" }
				hl.LineNr = { fg = ghostty.comment }
				hl.CursorLineNr = { fg = ghostty.yellow, bold = true }
				hl.WinSeparator = { fg = "#303840" }
				hl.Pmenu = { fg = colors.fg, bg = "#20262C" }
				hl.PmenuSel = { fg = ghostty.bg, bg = ghostty.blue, bold = true }
			end,
		},
		config = function(_, opts)
			require("tokyonight").setup(opts)
			vim.cmd.colorscheme("tokyonight-night")
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
						{ icon = " ", key = "f", desc = "Find File", action = ":lua Snacks.dashboard.pick('files')" },
						{ icon = " ", key = "n", desc = "New File", action = ":ene | startinsert" },
						{ icon = "󰱼 ", key = "g", desc = "Find Text", action = ":lua Snacks.dashboard.pick('live_grep')" },
						{ icon = " ", key = "r", desc = "Recent Files", action = ":lua Snacks.dashboard.pick('oldfiles')" },
						{ icon = " ", key = "c", desc = "Config", action = ":lua Snacks.dashboard.pick('files', { cwd = vim.fn.stdpath('config') })" },
						{ icon = "󰒲 ", key = "l", desc = "Lazy", action = ":Lazy", enabled = package.loaded.lazy ~= nil },
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
					{ section = "keys", gap = 1, padding = 1 },
					{
						pane = 2,
						section = "terminal",
						cmd = "colorscript -e square",
						height = 4,
						padding = 1,
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
						limit = 4,
					},
					{
						pane = 2,
						icon = " ",
						title = "Git Status",
						section = "terminal",
						enabled = function()
							return Snacks.git.get_root() ~= nil
						end,
						cmd = "git status --short --branch --renames",
						height = 6,
						padding = { 1, 1 },
						ttl = 300,
						indent = 2,
					},
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
