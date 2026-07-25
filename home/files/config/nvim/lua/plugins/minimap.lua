return {
	{
		"nvim-mini/mini.map",
		version = false,
		event = { "BufReadPost", "BufNewFile" },
		keys = {
			{
				"<leader>um",
				function()
					require("mini.map").toggle()
				end,
				desc = "Toggle minimap",
			},
			{
				"<leader>uM",
				function()
					require("mini.map").toggle_focus()
				end,
				desc = "Focus minimap",
			},
		},
		opts = function()
			local map = require("mini.map")

			return {
				integrations = {
					map.gen_integration.builtin_search(),
					map.gen_integration.diagnostic({
						error = "DiagnosticFloatingError",
						warn = "DiagnosticFloatingWarn",
						info = "DiagnosticFloatingInfo",
						hint = "DiagnosticFloatingHint",
					}),
					map.gen_integration.gitsigns({
						add = "GitSignsAdd",
						change = "GitSignsChange",
						delete = "GitSignsDelete",
					}),
				},
				symbols = {
					encode = map.gen_encode_symbols.dot("4x2"),
				},
				window = {
					width = 12,
					winblend = 25,
				},
			}
		end,
		config = function(_, opts)
			local map = require("mini.map")

			map.setup(opts)
			map.open()
		end,
	},
}
