local obsidian = require("config.obsidian")

return {
	{
		"windwp/nvim-autopairs",
		event = "InsertEnter",
		opts = {
			check_ts = true,
		},
	},
	{
		"obsidian-nvim/obsidian.nvim",
		version = "*",
		ft = { "markdown" },
		opts = function()
			return {
				legacy_commands = false,
				workspaces = {
					obsidian.workspace_spec(),
				},
			}
		end,
		config = function(_, opts)
			obsidian.setup(opts)
		end,
	},
	{
		"kylechui/nvim-surround",
		version = "^4.0.0",
		event = "VeryLazy",
		init = function()
			-- Flash owns `S` in Visual mode. Disable only nvim-surround's
			-- Visual defaults, then expose the same actions under `gs`/`gS`.
			vim.g.nvim_surround_no_visual_mappings = true
		end,
		opts = {},
		config = function(_, opts)
			require("nvim-surround").setup(opts)
			vim.keymap.set("x", "gs", "<Plug>(nvim-surround-visual)", {
				desc = "Add surround to selection",
			})
			vim.keymap.set("x", "gS", "<Plug>(nvim-surround-visual-line)", {
				desc = "Add linewise surround to selection",
			})
		end,
	},
	{
		"nvim-mini/mini.ai",
		event = "VeryLazy",
		opts = function()
			local ai = require("mini.ai")
			return {
				custom_textobjects = {
					-- Treesitter owns `af`/`if`; keep mini.ai's function-call
					-- object reachable through the otherwise unused `aF`/`iF`.
					F = ai.gen_spec.function_call(),
				},
				mappings = {
					around = "a",
					inside = "i",
					-- Keep Neovim 0.12 incremental selection and the builtin tag
					-- jumps available instead of claiming `an`/`in` and `g[`/`g]`.
					around_next = "",
					inside_next = "",
					around_last = "al",
					inside_last = "il",
					goto_left = "",
					goto_right = "",
				},
			}
		end,
	},
	{
		"chrisgrieser/nvim-spider",
		keys = {
			{
				"w",
				"<cmd>lua require('config.word_motion').motion('w')<cr>",
				mode = { "n", "o", "x" },
				desc = "Next word (skip punctuation)",
			},
			{
				"e",
				"<cmd>lua require('config.word_motion').motion('e')<cr>",
				mode = { "n", "o", "x" },
				desc = "End of word (skip punctuation)",
			},
			{
				"b",
				"<cmd>lua require('config.word_motion').motion('b')<cr>",
				mode = { "n", "o", "x" },
				desc = "Previous word (skip punctuation)",
			},
			{
				"ge",
				"<cmd>lua require('config.word_motion').motion('ge')<cr>",
				mode = { "n", "o", "x" },
				desc = "Previous word end (skip punctuation)",
			},
			-- Spider intentionally makes `cw` follow `w` exactly. Preserve Vim's
			-- familiar change-to-end behavior while still using Spider's `e` motion.
			{ "cw", "ce", mode = "n", remap = true, desc = "Change word" },
		},
		opts = {
			-- Skip syntax punctuation such as `.` in `value.method()`, but keep
			-- whitespace-delimited operators such as `==` as useful stops.
			skipInsignificantPunctuation = true,
			-- This change is about punctuation only; do not also alter established
			-- camelCase, snake_case, or kebab-case movement semantics.
			subwordMovement = false,
			consistentOperatorPending = false,
		},
	},
	{
		"Wansmer/treesj",
		keys = {
			{
				"gS",
				function()
					require("treesj").toggle()
				end,
				desc = "Toggle structural split/join",
			},
		},
		opts = {
			-- Keep the structural edit on the conventional split/join key without
			-- claiming the leader-based defaults used by the rest of this config.
			use_default_keymaps = false,
		},
	},
	{
		"nvim-mini/mini.move",
		event = "VeryLazy",
		opts = {
			-- Keep the global editing keys explicit so an upstream default change
			-- cannot silently alter muscle memory or claim a different mapping.
			mappings = {
				left = "<M-h>",
				right = "<M-l>",
				down = "<M-j>",
				up = "<M-k>",
				line_left = "<M-h>",
				line_right = "<M-l>",
				line_down = "<M-j>",
				line_up = "<M-k>",
			},
		},
	},
	{
		"nvim-mini/mini.align",
		event = "VeryLazy",
		opts = {
			mappings = {
				start = "ga",
				start_with_preview = "gA",
			},
		},
	},
}
