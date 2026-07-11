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
		"feline-nvim/feline.nvim",
		lazy = false,
		dependencies = { "nvim-tree/nvim-web-devicons" },
		config = function()
			local function setup_feline()
				package.loaded.feline = nil
				package.loaded["catppuccin.special.feline"] = nil

				local ctp_feline = require("catppuccin.special.feline")
				ctp_feline.setup()

				require("feline").setup({
					components = ctp_feline.get_statusline(),
				})
			end

			vim.api.nvim_create_autocmd("ColorScheme", {
				group = vim.api.nvim_create_augroup("dotfiles-feline-catppuccin", { clear = true }),
				pattern = "*",
				callback = setup_feline,
			})

			setup_feline()
		end,
	},
}
