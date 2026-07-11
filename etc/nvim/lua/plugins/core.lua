local catppuccin = require("config.catppuccin")
local colors = catppuccin.palette()
local fzf_colors = {
	match = colors.blue,
	info = colors.overlay0,
	prompt = colors.mauve,
	pointer = colors.peach,
	marker = colors.green,
	spinner = colors.sky,
}

local function set_fzf_highlights()
	vim.api.nvim_set_hl(0, "DotfilesFzfLuaNormal", { fg = colors.text, bg = colors.base })
	vim.api.nvim_set_hl(0, "DotfilesFzfLuaCursorLine", { fg = colors.text, bg = colors.surface0 })
	vim.api.nvim_set_hl(0, "DotfilesFzfLuaBorder", { fg = colors.overlay1, bg = colors.base })
	vim.api.nvim_set_hl(0, "DotfilesFzfLuaMatch", { fg = fzf_colors.match, bg = colors.base, bold = true })
	vim.api.nvim_set_hl(0, "DotfilesFzfLuaInfo", { fg = fzf_colors.info, bg = colors.base })
	vim.api.nvim_set_hl(0, "DotfilesFzfLuaPrompt", { fg = fzf_colors.prompt, bg = colors.base, bold = true })
	vim.api.nvim_set_hl(0, "DotfilesFzfLuaPointer", { fg = fzf_colors.pointer, bg = colors.base, bold = true })
	vim.api.nvim_set_hl(0, "DotfilesFzfLuaMarker", { fg = fzf_colors.marker, bg = colors.base, bold = true })
	vim.api.nvim_set_hl(0, "DotfilesFzfLuaSpinner", { fg = fzf_colors.spinner, bg = colors.base, bold = true })
	vim.api.nvim_set_hl(0, "DotfilesFzfLuaQuery", { fg = colors.text, bg = colors.base })
	vim.api.nvim_set_hl(0, "DotfilesFzfLuaTitle", { fg = colors.yellow, bg = colors.base, bold = true })
	vim.api.nvim_set_hl(0, "DotfilesFzfLuaTitleFlags", { fg = colors.subtext1, bg = colors.base })
	vim.api.nvim_set_hl(0, "DotfilesFzfLuaPreviewTitle", { fg = colors.sky, bg = colors.base, bold = true })
	vim.api.nvim_set_hl(0, "DotfilesFzfLuaBackdrop", { bg = colors.base })
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
			fzf_colors = { true },
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
				fzf = {
					normal = "DotfilesFzfLuaNormal",
					cursorline = "DotfilesFzfLuaCursorLine",
					match = "DotfilesFzfLuaMatch",
					border = "DotfilesFzfLuaBorder",
					scrollbar = "DotfilesFzfLuaBorder",
					separator = "DotfilesFzfLuaBorder",
					gutter = "DotfilesFzfLuaNormal",
					header = "DotfilesFzfLuaTitle",
					info = "DotfilesFzfLuaInfo",
					pointer = "DotfilesFzfLuaPointer",
					marker = "DotfilesFzfLuaMarker",
					spinner = "DotfilesFzfLuaSpinner",
					prompt = "DotfilesFzfLuaPrompt",
					query = "DotfilesFzfLuaQuery",
				},
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
				backdrop = false,
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
