local catppuccin = require("config.catppuccin")
local colors = catppuccin.palette()

local disabled_filetypes = {
	[""] = true,
	DiffviewFiles = true,
	NvimTree = true,
	TelescopePrompt = true,
	["dap-repl"] = true,
	["neo-tree"] = true,
	["noice"] = true,
	alpha = true,
	checkhealth = true,
	dashboard = true,
	fzf = true,
	git = true,
	help = true,
	lazy = true,
	mason = true,
	oil = true,
	prompt = true,
	qf = true,
	snacks_dashboard = true,
	terminal = true,
	Trouble = true,
}

local function scope_enabled(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	return not disabled_filetypes[vim.bo[buf].filetype] and vim.bo[buf].buftype == ""
end

local function set_scope_highlights()
	vim.api.nvim_set_hl(0, "MiniIndentscopeSymbol", { fg = colors.lavender, nocombine = true })
	vim.api.nvim_set_hl(0, "TreesitterContext", { fg = colors.text, bg = colors.surface0 })
	vim.api.nvim_set_hl(0, "TreesitterContextLineNumber", { fg = colors.overlay1, bg = colors.surface0 })
	vim.api.nvim_set_hl(0, "TreesitterContextBottom", { sp = colors.surface2, underline = true })
	vim.api.nvim_set_hl(
		0,
		"TreesitterContextLineNumberBottom",
		{ fg = colors.overlay1, bg = colors.surface0, sp = colors.surface2, underline = true }
	)
	vim.api.nvim_set_hl(0, "TreesitterContextSeparator", { fg = colors.surface2, bg = colors.surface0 })
end

return {
	{
		"nvim-mini/mini.indentscope",
		version = false,
		event = { "BufReadPost", "BufNewFile" },
		config = function()
			require("mini.indentscope").setup({
				draw = {
					animation = require("mini.indentscope").gen_animation.none(),
				},
				options = {
					try_as_border = true,
				},
				symbol = "│",
			})

			vim.api.nvim_create_autocmd("ColorScheme", {
				group = vim.api.nvim_create_augroup("dotfiles-mini-indentscope-colors", { clear = true }),
				pattern = "*",
				callback = set_scope_highlights,
			})
			set_scope_highlights()

			vim.api.nvim_create_autocmd("FileType", {
				group = vim.api.nvim_create_augroup("dotfiles-mini-indentscope-disable", { clear = true }),
				callback = function(args)
					if disabled_filetypes[vim.bo[args.buf].filetype] then
						vim.b[args.buf].miniindentscope_disable = true
					end
				end,
			})
		end,
	},
	{
		"nvim-treesitter/nvim-treesitter-context",
		event = { "BufReadPost", "BufNewFile" },
		opts = {
			max_lines = 3,
			min_window_height = 12,
			multiline_threshold = 4,
			mode = "cursor",
			separator = "─",
			on_attach = scope_enabled,
		},
		config = function(_, opts)
			require("treesitter-context").setup(opts)

			vim.api.nvim_create_autocmd("ColorScheme", {
				group = vim.api.nvim_create_augroup("dotfiles-treesitter-context-colors", { clear = true }),
				pattern = "*",
				callback = set_scope_highlights,
			})
			set_scope_highlights()
		end,
	},
	{
		"shellRaining/hlchunk.nvim",
		event = { "BufReadPre", "BufNewFile" },
		opts = {
			chunk = {
				enable = true,
				notify = false,
				use_treesitter = true,
				exclude_filetypes = disabled_filetypes,
				style = {
					{ fg = colors.mauve },
					{ fg = colors.blue },
				},
				chars = {
					horizontal_line = "─",
					vertical_line = "│",
					left_top = "╭",
					left_bottom = "╰",
					right_arrow = "─",
				},
			},
			indent = {
				enable = false,
			},
			line_num = {
				enable = false,
			},
			blank = {
				enable = false,
			},
		},
		config = function(_, opts)
			require("hlchunk").setup(opts)
		end,
	},
}
