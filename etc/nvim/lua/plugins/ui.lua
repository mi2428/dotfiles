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

-- XXX: Snacks.dashboard's startup path renders into a normal window, but the
-- generated buffer lines do not necessarily fill the full window width/height.
-- With transparent backgrounds enabled, any unpainted cells leak whatever was
-- previously on screen, which showed up as stray gutter/line-number artifacts.
-- Keep this full-window padding patch unless upstream guarantees the dashboard
-- always paints every visible cell.
local function patch_snacks_dashboard()
	local dashboard = require("snacks.dashboard")
	if dashboard._dotfiles_fullscreen_render_patched then
		return
	end

	local _, class = debug.getupvalue(dashboard.open, 1)
	if type(class) ~= "table" or class._dotfiles_fullscreen_render_patched then
		return
	end

	local original_render_buf = class.render_buf

	class.render_buf = function(self, extmarks)
		local width = self._size and self._size.width or vim.api.nvim_win_get_width(self.win)
		local height = vim.api.nvim_win_get_height(self.win)

		for index, line in ipairs(self.lines) do
			local padding = width - vim.api.nvim_strwidth(line)
			if padding > 0 then
				self.lines[index] = line .. string.rep(" ", padding)
			end
		end

		while #self.lines < height do
			self.lines[#self.lines + 1] = string.rep(" ", width)
		end

		return original_render_buf(self, extmarks)
	end

	class._dotfiles_fullscreen_render_patched = true
	dashboard._dotfiles_fullscreen_render_patched = true
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

local function set_dropbar_highlights()
	vim.api.nvim_set_hl(0, "DropBarIconUISeparator", { fg = colors.overlay1, bg = "NONE" })
	vim.api.nvim_set_hl(0, "DropBarIconUISeparatorMenu", { fg = colors.overlay1, bg = colors.mantle })
	vim.api.nvim_set_hl(0, "DropBarIconUIIndicator", { fg = colors.sapphire, bg = "NONE" })
	vim.api.nvim_set_hl(0, "DropBarIconUIPickPivot", { fg = colors.peach, bg = "NONE", bold = true })
	vim.api.nvim_set_hl(0, "DropBarCurrentContext", { fg = colors.text, bg = colors.surface0, bold = true })
	vim.api.nvim_set_hl(0, "DropBarCurrentContextIcon", { fg = colors.blue, bg = colors.surface0, bold = true })
	vim.api.nvim_set_hl(0, "DropBarCurrentContextName", { fg = colors.text, bg = colors.surface0, bold = true })
	vim.api.nvim_set_hl(0, "DropBarHover", { fg = colors.base, bg = colors.surface0, bold = true })
	vim.api.nvim_set_hl(0, "DropBarMenuCurrentContext", { fg = colors.lavender, bold = true })
	vim.api.nvim_set_hl(0, "DropBarMenuHoverEntry", { fg = colors.base, bg = colors.surface0 })
	vim.api.nvim_set_hl(0, "DropBarMenuHoverIcon", { fg = colors.blue, bg = colors.surface0 })
	vim.api.nvim_set_hl(0, "DropBarMenuHoverSymbol", { fg = colors.text, bg = colors.surface0, bold = true })
	vim.api.nvim_set_hl(0, "DropBarMenuNormalFloat", { fg = colors.text, bg = colors.mantle })
	vim.api.nvim_set_hl(0, "DropBarMenuFloatBorder", { fg = colors.surface2, bg = colors.mantle })
	vim.api.nvim_set_hl(0, "DropBarMenuSbar", { bg = colors.surface0 })
	vim.api.nvim_set_hl(0, "DropBarMenuThumb", { bg = colors.overlay0 })
	vim.api.nvim_set_hl(0, "DropBarPreview", { bg = colors.surface0 })
	vim.api.nvim_set_hl(0, "WinBar", { fg = colors.subtext1, bg = "NONE" })
	vim.api.nvim_set_hl(0, "WinBarNC", { fg = colors.overlay0, bg = "NONE" })
end

local function dropbar_enabled(buf, win)
	buf = buf or vim.api.nvim_get_current_buf()
	win = win or vim.api.nvim_get_current_win()

	if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_win_is_valid(win) then
		return false
	end

	if vim.api.nvim_win_get_config(win).relative ~= "" then
		return false
	end

	local filetype = vim.bo[buf].filetype
	local buftype = vim.bo[buf].buftype
	local disabled_filetypes = {
		"DiffviewFiles",
		"alpha",
		"dashboard",
		"fzf",
		"git",
		"help",
		"lazy",
		"mason",
		"neo-tree",
		"oil",
		"qf",
		"snacks_dashboard",
		"terminal",
		"toggleterm",
		"Trouble",
	}
	local disabled_buftypes = {
		"help",
		"nofile",
		"prompt",
		"quickfix",
		"terminal",
	}

	return not vim.tbl_contains(disabled_filetypes, filetype) and not vim.tbl_contains(disabled_buftypes, buftype)
end

local function bufferline_highlights()
	local current = colors.lavender
	local inactive = colors.surface0
	local fill = "NONE"
	local label = colors.crust

	return require("catppuccin.special.bufferline").get_theme({
		styles = { "bold" },
		custom = {
			all = {
				fill = { bg = fill },
				background = { fg = colors.subtext1, bg = inactive },
				buffer_visible = { fg = colors.text, bg = inactive },
				buffer_selected = { fg = colors.base, bg = current, style = { "bold" } },
				numbers = { fg = colors.overlay1, bg = inactive },
				numbers_visible = { fg = colors.overlay1, bg = inactive },
				numbers_selected = { fg = colors.base, bg = current, style = { "bold" } },
				separator = { fg = inactive, bg = fill },
				separator_visible = { fg = inactive, bg = fill },
				separator_selected = { fg = current, bg = fill },
				close_button = { fg = colors.overlay1, bg = inactive },
				close_button_visible = { fg = colors.overlay1, bg = inactive },
				close_button_selected = { fg = colors.base, bg = current },
				modified = { fg = colors.peach, bg = inactive },
				modified_visible = { fg = colors.peach, bg = inactive },
				modified_selected = { fg = colors.base, bg = current },
				duplicate = { fg = colors.overlay1, bg = inactive, style = { "italic" } },
				duplicate_visible = { fg = colors.overlay1, bg = inactive, style = { "italic" } },
				duplicate_selected = { fg = colors.overlay1, bg = current, style = { "italic" } },
				diagnostic = { fg = colors.overlay1, bg = inactive },
				diagnostic_visible = { fg = colors.overlay1, bg = inactive },
				diagnostic_selected = { fg = colors.base, bg = current },
				hint = { fg = colors.teal, bg = inactive },
				hint_visible = { fg = colors.teal, bg = inactive },
				hint_selected = { fg = colors.base, bg = current },
				info = { fg = colors.sky, bg = inactive },
				info_visible = { fg = colors.sky, bg = inactive },
				info_selected = { fg = colors.base, bg = current },
				warning = { fg = colors.yellow, bg = inactive },
				warning_visible = { fg = colors.yellow, bg = inactive },
				warning_selected = { fg = colors.base, bg = current },
				error = { fg = colors.red, bg = inactive },
				error_visible = { fg = colors.red, bg = inactive },
				error_selected = { fg = colors.base, bg = current },
				offset_separator = { fg = fill, bg = fill },
				tab_selected = { fg = colors.base, bg = current, style = { "bold" } },
				tab = { fg = colors.text, bg = inactive },
				tab_separator = { fg = inactive, bg = fill },
				tab_separator_selected = { fg = current, bg = fill },
				group_label = { fg = label, bg = colors.sapphire },
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
	local fill = "NONE"
	vim.api.nvim_set_hl(0, "BufferLinePillInactive", { fg = colors.surface0, bg = fill })
	vim.api.nvim_set_hl(0, "BufferLinePillSelected", { fg = colors.lavender, bg = fill })
end

local function set_bufferline_group_highlights()
	local inactive = colors.surface0
	local current = colors.lavender
	local fill = "NONE"
	local function set_group(name, accent)
		local prefix = "BufferLine" .. name
		vim.api.nvim_set_hl(0, prefix, { fg = colors.text, bg = inactive, sp = accent })
		vim.api.nvim_set_hl(0, prefix .. "Visible", { fg = colors.text, bg = inactive, sp = accent })
		vim.api.nvim_set_hl(0, prefix .. "Selected", { fg = colors.base, bg = current, bold = true, sp = accent })
		vim.api.nvim_set_hl(0, prefix .. "Separator", { fg = accent, bg = fill })
		vim.api.nvim_set_hl(0, prefix .. "Label", { fg = colors.crust, bg = accent, bold = true })
	end

	set_group("Docs", colors.sapphire)
	set_group("Tests", colors.green)
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
			local filetype = vim.bo[element.id].filetype
			if filetype == "" and element.path and element.path ~= "" then
				filetype = vim.filetype.match({ filename = element.path }) or ""
			end
			local is_markdown = filetype == "markdown"
			for index, segment in ipairs(comp) do
				if is_markdown and segment.highlight and segment.highlight:match("^BufferLineDevIcon") then
					table.insert(comp, index + 1, { text = " " })
					break
				end
			end

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
				diffview = true,
				gitsigns = true,
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
		"Bekaboo/dropbar.nvim",
		event = { "BufReadPost", "BufNewFile" },
		dependencies = { "nvim-tree/nvim-web-devicons" },
		opts = {
			bar = {
				enable = dropbar_enabled,
				padding = {
					left = 1,
					right = 1,
				},
			},
			icons = {
				ui = {
					bar = {
						separator = "  ",
					},
					menu = {
						indicator = " ",
					},
				},
			},
			menu = {
				quick_navigation = true,
			},
		},
		config = function(_, opts)
			local api = require("dropbar.api")

			require("dropbar").setup(opts)

			vim.keymap.set("n", "<leader>;", api.pick, { desc = "Pick breadcrumbs" })
			vim.keymap.set("n", "[;", api.goto_context_start, { desc = "Go to context start" })
			vim.keymap.set("n", "];", api.select_next_context, { desc = "Select next context" })

			vim.api.nvim_create_autocmd("ColorScheme", {
				group = vim.api.nvim_create_augroup("dotfiles-dropbar-catppuccin", { clear = true }),
				pattern = "*",
				callback = set_dropbar_highlights,
			})
			set_dropbar_highlights()
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
			picker = {
				sources = {
					explorer = {
						watch = false,
					},
				},
			},
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
							icon = " ",
							key = "d",
							desc = "Diff View",
							action = ":DiffviewOpen",
							enabled = vim.fn.system({ "git", "rev-parse", "--is-inside-work-tree" }):match("true")
								~= nil,
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
		config = function(_, opts)
			local snacks = require("snacks")

			snacks.setup(opts)
			patch_snacks_dashboard()
			snacks.config.styles.dashboard.wo.foldcolumn = "0"
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
					mode = "buffers",
					always_show_bufferline = true,
					show_buffer_close_icons = true,
					show_close_icon = false,
					modified_icon = "●",
					buffer_close_icon = "󰅖",
					separator_style = "pill",
					indicator = {
						style = "none",
					},
					numbers = function(opts)
						return opts.raise(opts.ordinal)
					end,
					show_duplicate_prefix = true,
					max_name_length = 24,
					tab_size = 24,
					diagnostics = false,
					name_formatter = function(tab)
						return tab.name
					end,
					offsets = {
						{
							filetype = "oil",
							text = "Oil",
							text_align = "center",
							separator = false,
						},
					},
					groups = {
						items = {
							{
								name = "docs",
								auto_close = false,
								highlight = {
									sp = colors.sapphire,
								},
								matcher = function(buf)
									local filetype = vim.bo[buf.id].filetype
									if filetype == "" and buf.path and buf.path ~= "" then
										filetype = vim.filetype.match({ filename = buf.path }) or ""
									end
									return filetype == "markdown" or filetype == "text" or filetype == "help"
								end,
							},
							{
								name = "tests",
								auto_close = false,
								highlight = {
									sp = colors.green,
								},
								matcher = function(buf)
									local path = buf.path or ""
									return path:match("_test%.go$") ~= nil
								end,
							},
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
			set_bufferline_group_highlights()
			vim.api.nvim_create_autocmd("ColorScheme", {
				group = vim.api.nvim_create_augroup("dotfiles-bufferline-pill", { clear = true }),
				pattern = "*",
				callback = function()
					set_bufferline_pill_highlights()
					set_bufferline_group_highlights()
					require("bufferline.ui").refresh()
				end,
			})
		end,
	},
}
