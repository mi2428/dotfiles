local fzf_theme = require("config.fzf")

local function refresh_folds_after_fzf()
	local buf = vim.api.nvim_get_current_buf()
	-- fzf-lua closes its terminal before Neovim has always completed the
	-- terminal-to-normal mode transition. UFO can obtain ranges in that gap but
	-- cannot apply them, leaving the first selected buffer permanently pending.
	-- Wait for normal mode before retrying the fold application.
	local function refresh(attempt)
		if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
			return
		end
		if vim.api.nvim_get_mode().mode ~= "n" then
			if attempt < 40 then
				vim.defer_fn(function()
					refresh(attempt + 1)
				end, 50)
			end
			return
		end

		local ok, ufo = pcall(require, "ufo")
		if ok and ufo.hasAttached(buf) then
			ufo.enableFold(buf)
		end
	end

	vim.defer_fn(function()
		refresh(1)
	end, 50)
end

local function fzf_open_file(selected, opts)
	require("fzf-lua.actions").file_edit_or_qf(selected, opts)
	refresh_folds_after_fzf()
end

local function fzf_open_in_current_window(selected, opts)
	local previous_buf = vim.api.nvim_get_current_buf()
	local previous_name = vim.api.nvim_buf_get_name(previous_buf)
	local was_modified = vim.bo[previous_buf].modified

	require("fzf-lua.actions").file_edit(selected, opts)
	refresh_folds_after_fzf()

	if not vim.api.nvim_buf_is_valid(previous_buf) or previous_buf == vim.api.nvim_get_current_buf() then
		return
	end
	if was_modified then
		local display_name = previous_name ~= "" and vim.fn.fnamemodify(previous_name, ":~:.") or "[No Name]"
		vim.notify("Unsaved buffer kept in buffer list: " .. display_name, vim.log.levels.WARN)
		return
	end

	vim.api.nvim_buf_delete(previous_buf, {})
end

local function fzf_open_in_vsplit(selected, opts)
	require("fzf-lua.actions").file_vsplit(selected, opts)
	vim.cmd("wincmd =")
	refresh_folds_after_fzf()
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
			lsp_file_methods = {
				enabled = true,
			},
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
			-- Keep picker titles, but do not spend vertical space on the
			-- automatically generated keybinding/action header.
			defaults = {
				headers = false,
			},
				actions = {
					files = {
						true,
						["enter"] = fzf_open_file,
						["ctrl-e"] = fzf_open_in_current_window,
						["ctrl-v"] = fzf_open_in_vsplit,
						["ctrl-q"] = function(selected, opts)
							require("fzf-lua.actions").file_sel_to_qf(selected, opts)
						end,
						["alt-q"] = false,
					},
				},
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
			buffers = {
				headers = false,
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
			local aws_regions = {
				"us-east-1",
				"us-east-2",
				"us-west-1",
				"us-west-2",
				"af-south-1",
				"ap-east-1",
				"ap-south-2",
				"ap-southeast-3",
				"ap-southeast-5",
				"ap-southeast-4",
				"ap-south-1",
				"ap-southeast-6",
				"ap-northeast-3",
				"ap-northeast-2",
				"ap-southeast-1",
				"ap-southeast-2",
				"ap-east-2",
				"ap-southeast-7",
				"ap-northeast-1",
				"ca-central-1",
				"ca-west-1",
				"eu-central-1",
				"eu-west-1",
				"eu-west-2",
				"eu-south-1",
				"eu-west-3",
				"eu-south-2",
				"eu-north-1",
				"eu-central-2",
				"il-central-1",
				"mx-central-1",
				"me-south-1",
				"me-central-1",
				"sa-east-1",
			}

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
					augend.constant.new({
						elements = { "yes", "no" },
						word = true,
						cyclic = true,
						preserve_case = true,
					}),
					augend.constant.new({
						elements = { "on", "off" },
						word = true,
						cyclic = true,
						preserve_case = true,
					}),
					augend.constant.new({
						elements = { "enable", "disable" },
						word = true,
						cyclic = true,
						preserve_case = true,
					}),
					augend.constant.new({
						elements = aws_regions,
						pattern_regexp = [[\C\%%(^\|[^-0-9a-z]\)\zs\(%s\)\ze\%%($\|[^-0-9a-z]\)]],
						cyclic = true,
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
	{
		"numToStr/Comment.nvim",
		event = "VeryLazy",
		opts = {},
	},
}
