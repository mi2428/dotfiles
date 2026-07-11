local function set_fzf_highlights()
	vim.api.nvim_set_hl(0, "DotfilesFzfLuaNormal", { link = "NormalFloat" })
	vim.api.nvim_set_hl(0, "DotfilesFzfLuaBorder", { link = "FloatBorder" })
	vim.api.nvim_set_hl(0, "DotfilesFzfLuaTitle", { link = "SnacksDashboardKey" })
	vim.api.nvim_set_hl(0, "DotfilesFzfLuaTitleFlags", { link = "SnacksDashboardDesc" })
	vim.api.nvim_set_hl(0, "DotfilesFzfLuaPreviewTitle", { link = "SnacksDashboardSpecial" })
	vim.api.nvim_set_hl(0, "DotfilesFzfLuaBackdrop", { link = "NormalFloat" })
end

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
		cmd = "FzfLua",
		opts = {
			"default",
			fzf_colors = {
				true,
				["bg"] = "-1",
				["gutter"] = "-1",
				["header"] = { "fg", "DotfilesFzfLuaTitle" },
			},
			hls = {
				normal = "DotfilesFzfLuaNormal",
				border = "DotfilesFzfLuaBorder",
				title = "DotfilesFzfLuaTitle",
				title_flags = "DotfilesFzfLuaTitleFlags",
				preview_normal = "DotfilesFzfLuaNormal",
				preview_border = "DotfilesFzfLuaBorder",
				preview_title = "DotfilesFzfLuaPreviewTitle",
				help_normal = "DotfilesFzfLuaNormal",
				help_border = "DotfilesFzfLuaBorder",
				backdrop = "DotfilesFzfLuaBackdrop",
			},
			files = {
				fd_opts = [[--color=never --type f --hidden --follow --exclude .git]],
			},
			grep = {
				rg_opts = [[--column --line-number --no-heading --color=always --smart-case --hidden --glob '!.git/**' -e]],
			},
			winopts = {
				height = 0.9,
				width = 0.8,
				backdrop = 100,
				preview = {
					layout = "vertical",
					vertical = "right:60%",
				},
			},
		},
		config = function(_, opts)
			require("fzf-lua").setup(opts)

			vim.api.nvim_create_autocmd("ColorScheme", {
				group = vim.api.nvim_create_augroup("dotfiles-fzf-highlights", { clear = true }),
				callback = set_fzf_highlights,
			})
			set_fzf_highlights()
		end,
	},
	{
		"nvim-lualine/lualine.nvim",
		event = "VeryLazy",
		dependencies = { "nvim-tree/nvim-web-devicons" },
		opts = {
			options = {
				theme = "auto",
				globalstatus = true,
				component_separators = { left = "│", right = "│" },
				section_separators = { left = "", right = "" },
			},
			sections = {
				lualine_a = { "mode" },
				lualine_b = { "branch", "diff", "diagnostics" },
				lualine_c = { { "filename", path = 1 } },
				lualine_x = { "encoding", "fileformat", "filetype" },
				lualine_y = { "progress" },
				lualine_z = { "location" },
			},
		},
	},
}
