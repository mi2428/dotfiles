return {
	{
		"folke/noice.nvim",
		event = "VeryLazy",
		dependencies = { "MunifTanjim/nui.nvim" },
		init = function()
			-- Noice owns only the command-line surface; keep the native message
			-- area hidden while its popup is active.
			vim.o.cmdheight = 0
		end,
		opts = {
			cmdline = {
				enabled = true,
				view = "cmdline_popup",
			},
			-- Snacks remains the owner of vim.notify and notification history,
			-- while regular command output continues through Neovim itself.
			messages = { enabled = false },
			notify = { enabled = false },
			-- blink.cmp remains the command-line completion engine and renderer.
			popupmenu = { enabled = false },
			-- Preserve the existing LSP hover, signature, progress, and markdown UI.
			lsp = {
				progress = { enabled = false },
				hover = { enabled = false },
				signature = { enabled = false },
				message = { enabled = false },
				override = {
					["vim.lsp.util.convert_input_to_markdown_lines"] = false,
					["vim.lsp.util.stylize_markdown"] = false,
					["cmp.entry.get_documentation"] = false,
				},
			},
			presets = {
				bottom_search = true,
				command_palette = true,
			},
		},
	},
}
