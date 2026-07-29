return {
	{
		"folke/noice.nvim",
		event = "VeryLazy",
		dependencies = { "MunifTanjim/nui.nvim" },
		init = function()
			-- Noice owns the command-line and regular message surfaces; keep the
			-- native command-line area hidden while its popups are active.
			vim.o.cmdheight = 0
		end,
		opts = {
			cmdline = {
				enabled = true,
				view = "cmdline_popup",
			},
			-- Let Noice render regular messages and confirmation prompts without
			-- mixing them into the Snacks notification history.
			messages = {
				enabled = true,
				view = "mini",
				view_error = "mini",
				view_warn = "mini",
			},
			-- Snacks remains the owner of vim.notify and notification history.
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
				bottom_search = false,
				command_palette = true,
			},
			views = {
				cmdline_popup = {
					position = { row = 3, col = "50%" },
				},
				confirm = {
					position = { row = 3, col = "50%" },
				},
			},
		},
	},
}
