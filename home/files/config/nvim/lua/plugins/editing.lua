return {
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
