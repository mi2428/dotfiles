local autocmd = vim.api.nvim_create_autocmd

autocmd("TextYankPost", {
	desc = "Highlight when yanking text",
	group = vim.api.nvim_create_augroup("dotfiles-highlight-yank", { clear = true }),
	callback = function()
		vim.highlight.on_yank()
	end,
})

autocmd({ "BufNewFile", "BufRead" }, {
	pattern = "*.go",
	group = vim.api.nvim_create_augroup("dotfiles-go-tabs", { clear = true }),
	callback = function()
		vim.opt_local.expandtab = false
		vim.opt_local.tabstop = 4
		vim.opt_local.shiftwidth = 4
		vim.opt_local.softtabstop = 4
	end,
})

autocmd("LspAttach", {
	group = vim.api.nvim_create_augroup("dotfiles-lsp-attach", { clear = true }),
	callback = function(args)
		local map = function(mode, lhs, rhs, desc)
			vim.keymap.set(mode, lhs, rhs, { buffer = args.buf, desc = desc })
		end

		map("n", "gd", vim.lsp.buf.definition, "LSP definition")
		map("n", "gD", vim.lsp.buf.declaration, "LSP declaration")
		map("n", "gr", vim.lsp.buf.references, "LSP references")
		map("n", "gI", vim.lsp.buf.implementation, "LSP implementation")
		map("n", "K", vim.lsp.buf.hover, "LSP hover")
		map("n", "<leader>rn", vim.lsp.buf.rename, "LSP rename")
		map({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, "LSP code action")
		map("n", "<leader>ds", vim.diagnostic.open_float, "Line diagnostics")
		map("n", "[d", vim.diagnostic.goto_prev, "Previous diagnostic")
		map("n", "]d", vim.diagnostic.goto_next, "Next diagnostic")
	end,
})
