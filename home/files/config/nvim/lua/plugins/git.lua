local catppuccin = require("config.catppuccin")
local diff_watch = require("config.diff_watch")
local review = require("config.review")
local colors = catppuccin.palette()

local function set_gitsigns_highlights()
	vim.api.nvim_set_hl(0, "GitSignsAdd", { fg = colors.green, bg = "NONE" })
	vim.api.nvim_set_hl(0, "GitSignsChange", { fg = colors.peach, bg = "NONE" })
	vim.api.nvim_set_hl(0, "GitSignsDelete", { fg = colors.red, bg = "NONE" })
	vim.api.nvim_set_hl(0, "GitSignsTopdelete", { fg = colors.red, bg = "NONE" })
	vim.api.nvim_set_hl(0, "GitSignsChangedelete", { fg = colors.yellow, bg = "NONE" })
	vim.api.nvim_set_hl(0, "GitSignsUntracked", { fg = colors.teal, bg = "NONE" })
	vim.api.nvim_set_hl(0, "GitSignsCurrentLineBlame", { fg = colors.overlay1, bg = "NONE", italic = true })
end

local function set_diffview_highlights()
	vim.api.nvim_set_hl(0, "DiffviewFilePanelTitle", { fg = colors.blue, bold = true })
	vim.api.nvim_set_hl(0, "DiffviewFilePanelCounter", { fg = colors.peach, bold = true })
	vim.api.nvim_set_hl(0, "DiffviewFilePanelRootPath", { fg = colors.overlay1, italic = true })
	vim.api.nvim_set_hl(0, "DiffviewPrimary", { fg = colors.blue, bold = true })
	vim.api.nvim_set_hl(0, "DiffviewSecondary", { fg = colors.mauve })
	vim.api.nvim_set_hl(0, "DiffviewDim1", { fg = colors.surface2 })
	vim.api.nvim_set_hl(0, "DiffviewNormal", { fg = colors.text, bg = "NONE" })
	vim.api.nvim_set_hl(0, "DiffviewCursorLine", { bg = colors.surface0 })
	-- Diffview maps actual deletions and alignment filler to separate groups.
	-- Keep real deletions red, but make the empty side of pure additions blank.
	vim.api.nvim_set_hl(0, "DiffviewDiffDeleteDim", { fg = "NONE", bg = "NONE" })
end

return {
	{
		"lewis6991/gitsigns.nvim",
		event = { "BufReadPre", "BufNewFile" },
		opts = {
			base = review.gitsigns_base() or diff_watch.gitsigns_base(),
			attach_to_untracked = diff_watch.is_active(),
			sign_priority = 100,
			signs = {
				add = { text = "▎" },
				change = { text = "▎" },
				delete = { text = "▎" },
				topdelete = { text = "▎" },
				changedelete = { text = "▎" },
				untracked = { text = "▎" },
			},
			signcolumn = true,
			numhl = false,
			linehl = false,
			current_line_blame = false,
			preview_config = {
				border = "rounded",
			},
		},
		init = function()
			vim.api.nvim_create_autocmd("ColorScheme", {
				group = vim.api.nvim_create_augroup("dotfiles-gitsigns-catppuccin", { clear = true }),
				pattern = "*",
				callback = set_gitsigns_highlights,
			})
			set_gitsigns_highlights()
		end,
		config = function(_, opts)
			require("gitsigns").setup(opts)

			-- Gitsigns may attach on BufReadPre before its configured base is
			-- applied. Reapply it so review and HEAD-watch buffers do not fall
			-- back to the Git index.
			local base = review.gitsigns_base() or diff_watch.gitsigns_base()
			if base then
				local function apply_configured_base()
					require("gitsigns").change_base(base, true)
				end
				local function apply_configured_base_after_attach()
					-- Gitsigns attaches asynchronously. Retry during startup so a
					-- slow initial attach cannot leave configured buffers on index base.
					for _, delay in ipairs({ 100, 500, 1000 }) do
						vim.defer_fn(apply_configured_base, delay)
					end
				end

				vim.api.nvim_create_autocmd({ "BufEnter", "VimEnter" }, {
					group = vim.api.nvim_create_augroup("dotfiles-gitsigns-configured-base", { clear = true }),
					callback = function()
						apply_configured_base_after_attach()
					end,
				})
				apply_configured_base_after_attach()
			end
		end,
	},
	{
		"sindrets/diffview.nvim",
		cmd = {
			"DiffviewOpen",
			"DiffviewClose",
			"DiffviewFileHistory",
			"DiffviewFocusFiles",
			"DiffviewToggleFiles",
			"DiffviewRefresh",
		},
		opts = {
			enhanced_diff_hl = true,
			hooks = {
				diff_buf_win_enter = function(_, win)
					vim.api.nvim_win_call(win, function()
						vim.opt_local.fillchars:append({ diff = " " })
					end)
				end,
			},
			view = {
				default = {
					layout = "diff2_horizontal",
					disable_diagnostics = false,
				},
			},
			default_args = {
				DiffviewOpen = { "--imply-local" },
			},
		},
		init = function()
			vim.api.nvim_create_autocmd("ColorScheme", {
				group = vim.api.nvim_create_augroup("dotfiles-diffview-catppuccin", { clear = true }),
				pattern = "*",
				callback = set_diffview_highlights,
			})
			set_diffview_highlights()
		end,
		config = function(_, opts)
			require("diffview").setup(opts)
			-- diffview.setup() recreates DiffviewDiffDeleteDim as a Comment link.
			-- Apply our blank filler style after the plugin finishes its highlights.
			set_diffview_highlights()
		end,
	},
}
