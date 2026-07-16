local function executable(name)
	return vim.fn.executable(name) == 1
end

return {
	{
		"nvim-neotest/neotest",
		cmd = { "Neotest" },
		keys = {
			{
				"<leader>tt",
				function()
					require("neotest").run.run()
				end,
				desc = "Run nearest test",
			},
			{
				"<leader>tf",
				function()
					require("neotest").run.run(vim.fn.expand("%"))
				end,
				desc = "Run file tests",
			},
			{
				"<leader>to",
				function()
					require("neotest").output.open({ enter = true, auto_close = true })
				end,
				desc = "Open test output",
			},
			{
				"<leader>ts",
				function()
					require("neotest").summary.toggle()
				end,
				desc = "Toggle test summary",
			},
		},
		dependencies = {
			"mrcjkb/rustaceanvim",
			"nvim-neotest/nvim-nio",
			"nvim-neotest/neotest-go",
			"nvim-neotest/neotest-python",
			"nvim-lua/plenary.nvim",
			"nvim-treesitter/nvim-treesitter",
		},
		opts = function()
			local adapters = {}

			if executable("go") then
				adapters[#adapters + 1] = require("neotest-go")({})
			end
			if executable("python3") then
				adapters[#adapters + 1] = require("neotest-python")({
					python = vim.fn.exepath("python3") ~= "" and vim.fn.exepath("python3") or "python3",
					runner = "pytest",
				})
			end
			if executable("cargo") then
				adapters[#adapters + 1] = require("rustaceanvim.neotest")
			end

			return {
				adapters = adapters,
				output = {
					open_on_run = true,
				},
				status = {
					virtual_text = false,
				},
				quickfix = {
					enabled = false,
				},
			}
		end,
		config = function(_, opts)
			require("neotest").setup(opts)
		end,
	},
}
