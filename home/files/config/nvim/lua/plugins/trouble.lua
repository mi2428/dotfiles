return {
	{
		"folke/trouble.nvim",
		cmd = "Trouble",
		keys = {
			{
				"<leader>xx",
				"<cmd>Trouble diagnostics toggle<cr>",
				desc = "Diagnostics (Trouble)",
			},
			{
				"<leader>xX",
				"<cmd>Trouble diagnostics toggle filter.buf=0<cr>",
				desc = "Buffer diagnostics (Trouble)",
			},
			{
				"<leader>xq",
				"<cmd>Trouble qflist toggle<cr>",
				desc = "Quickfix list (Trouble)",
			},
			{
				"<leader>xl",
				"<cmd>Trouble loclist toggle<cr>",
				desc = "Location list (Trouble)",
			},
		},
		opts = {},
	},
}
