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

local function bufferline_highlights()
	local current = colors.surface0
	local inactive = colors.mantle
	local fill = colors.crust

	return require("catppuccin.special.bufferline").get_theme({
		styles = { "bold" },
		custom = {
			all = {
				fill = { bg = fill },
				background = { fg = colors.subtext1, bg = inactive },
				buffer_visible = { fg = colors.text, bg = inactive },
				buffer_selected = { fg = colors.text, bg = current, style = { "bold" } },
				separator = { fg = inactive, bg = fill },
				separator_visible = { fg = inactive, bg = fill },
				separator_selected = { fg = current, bg = fill },
				close_button = { fg = colors.overlay1, bg = inactive },
				close_button_visible = { fg = colors.overlay1, bg = inactive },
				close_button_selected = { fg = colors.peach, bg = current },
				modified = { fg = colors.peach, bg = inactive },
				modified_visible = { fg = colors.peach, bg = inactive },
				modified_selected = { fg = colors.peach, bg = current },
				duplicate = { fg = colors.overlay1, bg = inactive, style = { "italic" } },
				duplicate_visible = { fg = colors.overlay1, bg = inactive, style = { "italic" } },
				duplicate_selected = { fg = colors.overlay1, bg = current, style = { "italic" } },
				diagnostic = { fg = colors.overlay1, bg = inactive },
				diagnostic_visible = { fg = colors.overlay1, bg = inactive },
				diagnostic_selected = { fg = colors.overlay1, bg = current },
				hint = { fg = colors.teal, bg = inactive },
				hint_visible = { fg = colors.teal, bg = inactive },
				hint_selected = { fg = colors.teal, bg = current },
				info = { fg = colors.sky, bg = inactive },
				info_visible = { fg = colors.sky, bg = inactive },
				info_selected = { fg = colors.sky, bg = current },
				warning = { fg = colors.yellow, bg = inactive },
				warning_visible = { fg = colors.yellow, bg = inactive },
				warning_selected = { fg = colors.yellow, bg = current },
				error = { fg = colors.red, bg = inactive },
				error_visible = { fg = colors.red, bg = inactive },
				error_selected = { fg = colors.red, bg = current },
			},
		},
	})
end

local function setup_bufferline_style()
	local constants = require("bufferline.constants")
	constants.sep_names.pill = "pill"
	constants.sep_chars.pill = { "", "" }
end

local function set_bufferline_pill_highlights()
	local fill = colors.crust
	vim.api.nvim_set_hl(0, "BufferLinePillInactive", { fg = colors.mantle, bg = fill })
	vim.api.nvim_set_hl(0, "BufferLinePillSelected", { fg = colors.surface0, bg = fill })
end

local function setup_bufferline_pill_renderer()
	local ui = require("bufferline.ui")
	if ui._dotfiles_pill_patched then
		return
	end

	local orig_element = ui.element

	ui.element = function(current_state, element)
		local item = orig_element(current_state, element)
		local orig_component = item.component

		item.component = function(next_item)
			local comp = orig_component(next_item)
			local filtered = {}

			for _, segment in ipairs(comp) do
				if not (segment.highlight and segment.highlight:match("^BufferLineIndicator")) then
					filtered[#filtered + 1] = segment
				end
			end

			comp = filtered
			local last = comp[#comp]

			if last and last.highlight and last.highlight:match("^BufferLineSeparator") then
				table.remove(comp, #comp)
			end

			local current_hl = element:current() and "BufferLinePillSelected" or "BufferLinePillInactive"

			table.insert(comp, 1, { highlight = current_hl, text = "" })
			table.insert(comp, { highlight = current_hl, text = "" })

			return comp
		end

		return item
	end

	ui._dotfiles_pill_patched = true
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
				bufferline = true,
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
	{
		"akinsho/bufferline.nvim",
		version = "*",
		event = "VeryLazy",
		dependencies = { "nvim-tree/nvim-web-devicons" },
		opts = function()
			return {
				options = {
					mode = "tabs",
					always_show_bufferline = true,
					show_buffer_close_icons = true,
					show_close_icon = false,
					modified_icon = "●",
					buffer_close_icon = "󰅖",
					separator_style = "pill",
					indicator = {
						style = "none",
					},
					show_duplicate_prefix = false,
					max_name_length = 24,
					tab_size = 24,
					diagnostics = "nvim_lsp",
					name_formatter = function(tab)
						return tab.name
					end,
					diagnostics_indicator = function(_, _, diagnostics_dict)
						local parts = {}
						if diagnostics_dict.error then
							parts[#parts + 1] = " " .. diagnostics_dict.error
						end
						if diagnostics_dict.warning then
							parts[#parts + 1] = " " .. diagnostics_dict.warning
						end
						if diagnostics_dict.info then
							parts[#parts + 1] = " " .. diagnostics_dict.info
						end
						if diagnostics_dict.hint then
							parts[#parts + 1] = "󰌵 " .. diagnostics_dict.hint
						end
						return #parts > 0 and (" " .. table.concat(parts, " ")) or ""
					end,
					offsets = {
						{
							filetype = "oil",
							text = "Oil",
							text_align = "center",
							separator = false,
						},
					},
				},
				highlights = bufferline_highlights(),
			}
		end,
		config = function(_, opts)
			setup_bufferline_style()
			setup_bufferline_pill_renderer()
			require("bufferline").setup(opts)
			set_bufferline_pill_highlights()
			vim.api.nvim_create_autocmd("ColorScheme", {
				group = vim.api.nvim_create_augroup("dotfiles-bufferline-pill", { clear = true }),
				pattern = "*",
				callback = function()
					set_bufferline_pill_highlights()
					require("bufferline.ui").refresh()
				end,
			})
		end,
	},
}
