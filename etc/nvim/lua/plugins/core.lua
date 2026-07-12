local fzf_theme = require("config.fzf")

return {
	{
		"nvim-tree/nvim-web-devicons",
		lazy = true,
	},
	{
		"nvim-lua/plenary.nvim",
		lazy = true,
		branch = "master",
	},
	{
		"stevearc/oil.nvim",
		lazy = false,
		dependencies = { "nvim-tree/nvim-web-devicons" },
		opts = {
			default_file_explorer = true,
			columns = { "icon", "permissions", "size", "mtime" },
			view_options = {
				show_hidden = true,
			},
			keymaps = {
				["<C-h>"] = false,
				["<C-l>"] = false,
			},
		},
	},
	{
		"ibhagwan/fzf-lua",
		lazy = false,
		dependencies = { "nvim-tree/nvim-web-devicons" },
		opts = {
			"default",
			fzf_colors = false,
			fzf_opts = vim.tbl_extend("force", fzf_theme.ui_opts(), {
				["--color"] = fzf_theme.color_spec({ transparent_background = true }),
			}),
			files = {
				fd_opts = [[--color=never --type f --hidden --follow --exclude .git]],
			},
			grep = {
				rg_opts = [[--column --line-number --no-heading --color=always --smart-case --hidden --glob '!.git/**' -e]],
			},
			winopts = {
				height = 0.9,
				width = 0.8,
				backdrop = false,
				preview = {
					layout = "vertical",
					vertical = "right:60%",
				},
			},
		},
	},
	{
		"rebelot/heirline.nvim",
		lazy = false,
		dependencies = { "nvim-tree/nvim-web-devicons" },
		config = function()
			local function setup_heirline()
				package.loaded["config.heirline_statusline"] = nil
				require("config.heirline_statusline").setup()
			end

			vim.api.nvim_create_autocmd("ColorScheme", {
				group = vim.api.nvim_create_augroup("dotfiles-heirline-catppuccin", { clear = true }),
				pattern = "*",
				callback = setup_heirline,
			})

			setup_heirline()
		end,
	},
	{
		"monaqa/dial.nvim",
		event = "VeryLazy",
		config = function()
			local augend = require("dial.augend")

			require("dial.config").augends:register_group({
				default = {
					augend.integer.alias.decimal_int,
					augend.integer.alias.hex,
					augend.date.alias["%Y/%m/%d"],
					augend.date.alias["%Y-%m-%d"],
					augend.date.alias["%m/%d"],
					augend.date.alias["%H:%M"],
					augend.constant.alias.bool,
					augend.constant.alias.Bool,
					augend.constant.new({ elements = { "yes", "no" }, word = true, cyclic = true, preserve_case = true }),
					augend.constant.new({ elements = { "on", "off" }, word = true, cyclic = true, preserve_case = true }),
					augend.constant.new({
						elements = { "enable", "disable" },
						word = true,
						cyclic = true,
						preserve_case = true,
					}),
				},
			})

			vim.keymap.set("n", "<C-a>", require("dial.map").inc_normal(), { desc = "Increment / toggle" })
			vim.keymap.set("n", "<C-x>", require("dial.map").dec_normal(), { desc = "Decrement / toggle" })
			vim.keymap.set("x", "<C-a>", require("dial.map").inc_visual(), { desc = "Increment / toggle" })
			vim.keymap.set("x", "<C-x>", require("dial.map").dec_visual(), { desc = "Decrement / toggle" })
			vim.keymap.set("n", "g<C-a>", require("dial.map").inc_gnormal(), { desc = "Increment / toggle" })
			vim.keymap.set("n", "g<C-x>", require("dial.map").dec_gnormal(), { desc = "Decrement / toggle" })
			vim.keymap.set("x", "g<C-a>", require("dial.map").inc_gvisual(), { desc = "Increment / toggle" })
			vim.keymap.set("x", "g<C-x>", require("dial.map").dec_gvisual(), { desc = "Decrement / toggle" })
		end,
	},
}
