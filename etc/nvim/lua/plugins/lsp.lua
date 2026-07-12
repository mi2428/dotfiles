local function executable(name)
	return vim.fn.executable(name) == 1
end

return {
	{
		"saghen/blink.cmp",
		version = "1.*",
		event = { "InsertEnter", "CmdlineEnter" },
		dependencies = { "rafamadriz/friendly-snippets" },
		opts = {
			keymap = {
				preset = "default",
				["<Tab>"] = { "select_next", "fallback" },
				["<S-Tab>"] = { "select_prev", "fallback" },
			},
			appearance = {
				nerd_font_variant = "mono",
			},
			completion = {
				documentation = {
					auto_show = true,
					auto_show_delay_ms = 200,
				},
				menu = {
					auto_show = true,
				},
				list = {
					selection = {
						preselect = false,
						auto_insert = false,
					},
				},
			},
			sources = {
				default = { "lsp", "path", "buffer", "snippets" },
				per_filetype = {
					codecompanion = { "codecompanion" },
				},
			},
			fuzzy = {
				implementation = "prefer_rust_with_warning",
			},
			signature = {
				enabled = true,
			},
		},
		opts_extend = { "sources.default" },
	},
	{
		"dnlhc/glance.nvim",
		cmd = "Glance",
		opts = {},
	},
	{
		"rachartier/tiny-inline-diagnostic.nvim",
		event = "LspAttach",
		priority = 1000,
		opts = {
			options = {
				use_icons_from_diagnostic = true,
			},
		},
	},
	{
		"neovim/nvim-lspconfig",
		event = { "BufReadPre", "BufNewFile" },
		config = function()
			local blink = require("blink.cmp")
			local capabilities = blink.get_lsp_capabilities()
			local enabled_servers = {}

			vim.diagnostic.config({
				severity_sort = true,
				float = { border = "rounded" },
				underline = true,
				signs = {
					text = {
						[vim.diagnostic.severity.ERROR] = "●",
						[vim.diagnostic.severity.WARN] = "●",
						[vim.diagnostic.severity.INFO] = "●",
						[vim.diagnostic.severity.HINT] = "●",
					},
				},
				virtual_text = false,
			})

			local function enable(server, cmd, config)
				if not executable(cmd) then
					return
				end

				vim.lsp.config(
					server,
					vim.tbl_deep_extend("force", {
						capabilities = capabilities,
					}, config or {})
				)
				table.insert(enabled_servers, server)
			end

			enable("lua_ls", "lua-language-server", {
				settings = {
					Lua = {
						completion = {
							callSnippet = "Replace",
						},
						diagnostics = {
							globals = { "vim" },
						},
					},
				},
			})

			enable("gopls", "gopls", {
				settings = {
					gopls = {
						analyses = {
							modernize = true,
						},
						gofumpt = true,
						staticcheck = true,
						usePlaceholders = true,
					},
				},
			})

			if executable("pyright-langserver") then
				enable("pyright", "pyright-langserver")
			elseif executable("pylsp") then
				enable("pylsp", "pylsp")
			end

			enable("terraformls", "terraform-ls")
			enable("bashls", "bash-language-server")
			enable("jsonls", "vscode-json-language-server")

			for _, server in ipairs(enabled_servers) do
				vim.lsp.enable(server)
			end
		end,
	},
	{
		"stevearc/conform.nvim",
		event = { "BufWritePre" },
		opts = {
			notify_on_error = false,
			format_on_save = function(bufnr)
				if vim.bo[bufnr].buftype ~= "" then
					return
				end

				return {
					timeout_ms = 500,
					lsp_format = "fallback",
				}
			end,
			formatters_by_ft = {
				go = { "goimports", "gofmt" },
				lua = { "stylua" },
				python = { "ruff_format", "isort", "black" },
				sh = { "shfmt" },
				terraform = { "terraform_fmt" },
				["terraform-vars"] = { "terraform_fmt" },
			},
		},
	},
}
