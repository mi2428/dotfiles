local function executable(name)
	return vim.fn.executable(name) == 1
end

local function resolve_rust_analyzer()
	local path = vim.fn.exepath("rust-analyzer")
	if path ~= "" then
		return path
	end

	if not executable("rustup") then
		return nil
	end

	local result = vim.system({ "rustup", "which", "rust-analyzer" }, { text = true }):wait()
	if result.code ~= 0 then
		return nil
	end

	local resolved = vim.trim(result.stdout or "")
	return resolved ~= "" and resolved or nil
end

local function install_lsp_watch_registration_filter()
	if vim.g.dotfiles_lsp_watch_registration_filter_installed then
		return
	end

	vim.g.dotfiles_lsp_watch_registration_filter_installed = true

	local original = vim.lsp.handlers["client/registerCapability"]

	vim.lsp.handlers["client/registerCapability"] = function(err, params, ctx, config)
		if params and params.registrations then
			local filtered_params = vim.deepcopy(params)
			local registrations = {}

			for _, registration in ipairs(filtered_params.registrations) do
				if registration.method ~= "workspace/didChangeWatchedFiles" then
					registrations[#registrations + 1] = registration
				else
					-- Some servers register watchers rooted at paths that do not
					-- exist on this machine. Drop only those entries and keep the
					-- rest of the capability registration intact.
					local watchers = ((registration or {}).registerOptions or {}).watchers or {}
					local kept_watchers = {}

					for _, watcher in ipairs(watchers) do
						local glob_pattern = watcher.globPattern
						if type(glob_pattern) ~= "table" or type(glob_pattern.baseUri) ~= "string" then
							kept_watchers[#kept_watchers + 1] = watcher
						else
							local base_path = vim.uri_to_fname(glob_pattern.baseUri)
							if vim.uv.fs_stat(base_path) ~= nil then
								kept_watchers[#kept_watchers + 1] = watcher
							end
						end
					end

					if #kept_watchers > 0 then
						registration.registerOptions.watchers = kept_watchers
						registrations[#registrations + 1] = registration
					end
				end
			end

			filtered_params.registrations = registrations
			params = filtered_params
		end

		return original(err, params, ctx, config)
	end
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
			install_lsp_watch_registration_filter()

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
				if cmd and vim.fn.executable(cmd) ~= 1 and vim.uv.fs_stat(cmd) == nil then
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

			local rust_analyzer = resolve_rust_analyzer()
			if rust_analyzer then
				enable("rust_analyzer", rust_analyzer, {
					cmd = { rust_analyzer },
					settings = {
						["rust-analyzer"] = {
							checkOnSave = true,
							check = {
								command = "check",
								allTargets = false,
							},
							cargo = {
								allTargets = false,
							},
						},
					},
				})
			end

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
