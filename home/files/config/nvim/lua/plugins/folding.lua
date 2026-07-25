return {
	{
		"kevinhwang91/promise-async",
		lazy = true,
	},
	{
		"kevinhwang91/nvim-ufo",
		event = "VeryLazy",
		dependencies = { "kevinhwang91/promise-async" },
		opts = {
			provider_selector = function(_, _, _)
				return { "treesitter", "indent" }
			end,
		},
		config = function(_, opts)
			local ufo = require("ufo")
			ufo.setup(opts)

			-- UFO does not rebuild its manual folds when 'foldenable' is
			-- switched back on with the built-in zi/zN commands.
			vim.keymap.set("n", "zi", function()
				if vim.wo.foldenable then
					vim.wo.foldenable = false
				else
					vim.wo.foldenable = true
					ufo.enableFold()
				end
			end, { desc = "Toggle folds" })

			vim.keymap.set("n", "zN", function()
				vim.wo.foldenable = true
				ufo.enableFold()
			end, { desc = "Enable folds" })
		end,
	},
}
