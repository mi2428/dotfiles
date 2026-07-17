local function executable(name)
	return vim.fn.executable(name) == 1
end

local function normalize_path(path)
	if path == nil or path == "" then
		return nil
	end
	return vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
end

local function file_exists(path)
	return path ~= nil and vim.uv.fs_stat(path) ~= nil
end

local function find_helm_chart_root(path)
	path = normalize_path(path)
	if path == nil then
		return nil
	end

	local start = file_exists(path) and vim.fn.isdirectory(path) == 1 and path or vim.fs.dirname(path)
	local matches = vim.fs.find("Chart.yaml", {
		path = start,
		upward = true,
		type = "file",
		stop = vim.uv.os_homedir(),
	})

	if #matches == 0 then
		return nil
	end

	return vim.fs.dirname(matches[1])
end

local function is_helm_values_file(path)
	local name = vim.fs.basename(path or "")
	return name == "Chart.yaml" or name:match("^values.*%.ya?ml$") ~= nil
end

local function is_kubernetes_buffer(bufnr)
	local path = vim.api.nvim_buf_get_name(bufnr)
	local name = vim.fs.basename(path)
	if name == "kustomization.yaml" or name == "kustomization.yml" then
		return true
	end

	local line_count = math.min(vim.api.nvim_buf_line_count(bufnr), 200)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, line_count, false)
	local has_api_version = false
	local has_kind = false

	for _, line in ipairs(lines) do
		if not has_api_version and line:match("^%s*apiVersion:%s*[%w%p]+") then
			has_api_version = true
		end
		if not has_kind and line:match("^%s*kind:%s*[%w%p]+") then
			has_kind = true
		end
		if has_api_version and has_kind then
			return true
		end
	end

	return false
end

local function parse_kubeconform(output, bufnr, linter_cwd)
	if output == nil or output == "" or not vim.api.nvim_buf_is_valid(bufnr) then
		return {}
	end

	local ok, decoded = pcall(vim.json.decode, output)
	if not ok or type(decoded) ~= "table" then
		return {}
	end

	local diagnostics = {}
	local buffer_path = normalize_path(vim.api.nvim_buf_get_name(bufnr))

	for _, resource in ipairs(decoded.resources or {}) do
		local filename = resource.filename
		local status = resource.status
		if filename and status and status ~= "VALID" then
			local resource_path
			if filename:match("^/") or filename:match("^%a:[/\\]") then
				resource_path = normalize_path(filename)
			else
				resource_path = normalize_path(vim.fs.joinpath(linter_cwd, filename))
			end

			if resource_path == buffer_path then
				local kind = resource.kind and (" [" .. resource.kind .. "]") or ""
				diagnostics[#diagnostics + 1] = {
					lnum = 0,
					col = 0,
					end_lnum = 0,
					end_col = 0,
					severity = vim.diagnostic.severity.ERROR,
					source = "kubeconform",
					message = (resource.msg or "Invalid Kubernetes manifest") .. kind,
				}
			end
		end
	end

	return diagnostics
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
		"towolf/vim-helm",
		lazy = false,
	},
	{
		"pearofducks/ansible-vim",
		ft = { "yaml.ansible", "ansible_hosts" },
	},
	{
		"folke/lazydev.nvim",
		ft = "lua",
		opts = {
			library = {
				{ path = "${3rd}/luv/library", words = { "vim%.uv" } },
			},
		},
	},
	{
		"saghen/blink.cmp",
		version = "1.*",
		event = { "InsertEnter", "CmdlineEnter" },
		dependencies = { "rafamadriz/friendly-snippets" },
		opts = {
			keymap = {
				preset = "default",
				["<C-l>"] = { "show", "fallback" },
				["<C-o>"] = { "select_and_accept", "fallback" },
				["<C-y>"] = false,
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
					window = {
						border = "rounded",
						winblend = 0,
					},
				},
				menu = {
					border = "rounded",
					winblend = 0,
					-- Only show a menu when an attached LSP can provide completions. This keeps
					-- prose, extensionless, and other unstructured buffers free of buffer-word
					-- suggestions (including Japanese text in Markdown).
					auto_show = function()
						for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
							if client:supports_method("textDocument/completion", { bufnr = 0 }) then
								return true
							end
						end
						return false
					end,
				},
				list = {
					selection = {
						preselect = false,
						auto_insert = false,
					},
				},
			},
			sources = {
				default = { "lazydev", "lsp", "path", "buffer", "snippets" },
				providers = {
					lazydev = {
						name = "LazyDev",
						module = "lazydev.integrations.blink",
						score_offset = 100,
					},
				},
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
		config = function()
			local glance = require("glance")

			glance.setup({
				border = {
					enable = true,
				},
				hooks = {
					before_open = function(results, open)
						open(results)
						vim.schedule(glance.actions.enter_win("preview"))
					end,
				},
			})
		end,
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
		"mrcjkb/rustaceanvim",
		version = "^6",
		ft = { "rust" },
		init = function()
			local rust_analyzer = resolve_rust_analyzer()

			vim.g.rustaceanvim = {
				server = {
					cmd = rust_analyzer and { rust_analyzer } or nil,
					default_settings = {
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
				},
			}
		end,
	},
	{
		"saecki/crates.nvim",
		event = { "BufRead Cargo.toml", "BufNewFile Cargo.toml" },
		dependencies = { "nvim-lua/plenary.nvim" },
		opts = {
			completion = {
				crates = {
					enabled = true,
				},
			},
		},
	},
	{
		"neovim/nvim-lspconfig",
		event = { "BufReadPre", "BufNewFile" },
		dependencies = { "b0o/SchemaStore.nvim" },
		config = function()
			install_lsp_watch_registration_filter()

			local blink = require("blink.cmp")
			local schemastore = require("schemastore")
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

			if executable("pyright-langserver") then
				enable("pyright", "pyright-langserver")
			elseif executable("pylsp") then
				enable("pylsp", "pylsp")
			end

			enable("terraformls", "terraform-ls")
			enable("bashls", "bash-language-server")
			enable("dockerls", "docker-langserver")
			enable("helm_ls", "helm_ls", {
				filetypes = { "helm" },
				settings = {
					["helm-ls"] = {
						yamlls = {
							path = "yaml-language-server",
							config = {
								schemas = {
									kubernetes = "templates/**",
								},
							},
						},
					},
				},
			})
			enable("ansiblels", "ansible-language-server", {
				filetypes = { "ansible", "yaml.ansible" },
				settings = {
					ansible = {
						ansible = {
							path = "ansible",
						},
						python = {
							interpreterPath = "python3",
						},
						validation = {
							enabled = true,
							lint = {
								enabled = true,
								path = "ansible-lint",
							},
						},
					},
				},
			})
			enable("jsonls", "vscode-json-language-server")
			enable("yamlls", "yaml-language-server", {
				filetypes = { "ansible", "yaml", "yaml.ansible", "yaml.docker-compose", "yaml.gitlab" },
				settings = {
					redhat = {
						telemetry = {
							enabled = false,
						},
					},
					yaml = {
						format = {
							enable = true,
						},
						keyOrdering = false,
						schemaStore = {
							enable = false,
							url = "",
						},
						schemas = schemastore.yaml.schemas(),
						validate = true,
					},
				},
			})

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
				python = { "ruff_organize_imports", "ruff_format" },
				rust = { "rustfmt" },
				sh = { "shfmt" },
				terraform = { "terraform_fmt" },
				["terraform-vars"] = { "terraform_fmt" },
			},
		},
	},
	{
		"mfussenegger/nvim-lint",
		event = { "BufReadPost", "BufWritePost", "InsertLeave" },
		config = function()
			local lint = require("lint")
			local parser = require("lint.parser")
			local lint_augroup = vim.api.nvim_create_augroup("dotfiles-nvim-lint", { clear = true })
			local helm_severities = {
				ERROR = vim.diagnostic.severity.ERROR,
				WARNING = vim.diagnostic.severity.WARN,
				INFO = vim.diagnostic.severity.INFO,
			}

			lint.linters.helm_lint = {
				cmd = "helm",
				args = { "lint", "." },
				stdin = false,
				append_fname = false,
				stream = "stdout",
				ignore_exitcode = true,
				parser = parser.from_pattern(
					"^%[(%u+)%]%s+([^:]+):%s+(.+)$",
					{ "severity", "file", "message" },
					helm_severities
				),
			}

			lint.linters.kubeconform = {
				cmd = "kubeconform",
				args = { "-summary", "-output", "json", "-ignore-missing-schemas" },
				stdin = false,
				append_fname = true,
				ignore_exitcode = true,
				parser = parse_kubeconform,
			}

			lint.linters_by_ft = {
				ansible = { "yamllint" },
				dockerfile = { "hadolint" },
				go = { "golangcilint" },
				python = { "ruff" },
				terraform = { "tflint" },
				["terraform-vars"] = { "tflint" },
				yaml = { "yamllint" },
				["yaml.ansible"] = { "yamllint" },
			}

			local function try_lint()
				lint.try_lint()

				local bufnr = vim.api.nvim_get_current_buf()
				local path = vim.api.nvim_buf_get_name(bufnr)
				local filetype = vim.bo[bufnr].filetype

				if filetype == "helm" then
					local chart_root = find_helm_chart_root(path)
					if chart_root then
						lint.try_lint("helm_lint", { cwd = chart_root })
					end
					if is_helm_values_file(path) then
						lint.try_lint("yamllint")
					end
				elseif filetype:match("^yaml") and is_kubernetes_buffer(bufnr) then
					lint.try_lint("kubeconform")
				end

				local path = vim.api.nvim_buf_get_name(0)
				if path:match("/%.github/workflows/.*%.ya?ml$") then
					lint.try_lint("actionlint")
				end
			end

			vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
				group = lint_augroup,
				callback = try_lint,
			})
		end,
	},
}
