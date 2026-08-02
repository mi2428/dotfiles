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

local function parent_directory(path)
	path = normalize_path(path)
	return path and vim.fs.dirname(path) or nil
end

local function project_root(path, markers)
	path = normalize_path(path)
	return path and vim.fs.root(path, markers) or nil
end

local function golangcilint_options(path)
	local directory = parent_directory(path)
	if directory == nil then
		return nil
	end
	local in_workspace = project_root(path, { "go.mod", "go.work" }) ~= nil
	return {
		cwd = directory,
		wrap_linter = function(linter)
			-- nvim-lint decides between a package directory and a single file
			-- when its module is first required, using Neovim's cwd. Resolve that
			-- choice per buffer instead so editing another repository cannot make
			-- typecheck analyze one Go file in isolation.
			if linter.args and #linter.args > 0 then
				linter.args[#linter.args] = in_workspace and "." or vim.fs.basename(path)
			end
			return linter
		end,
	}
end

local function tflint_options(path)
	local directory = parent_directory(path)
	if directory == nil then
		return nil
	end
	local config_root = project_root(path, ".tflint.hcl")
	return {
		cwd = directory,
		wrap_linter = function(linter)
			-- A shared config may cover many Terraform modules. Keep its rules,
			-- but lint only the module containing the current buffer.
			local args = {}
			for _, arg in ipairs(linter.args or {}) do
				if arg ~= "--recursive" then
					args[#args + 1] = arg
				end
			end
			if config_root then
				args[#args + 1] = "--config=" .. vim.fs.joinpath(config_root, ".tflint.hcl")
			end
			linter.args = args
			return linter
		end,
	}
end

local function hadolint_options(path)
	local directory = parent_directory(path)
	if directory == nil then
		return nil
	end
	return {
		cwd = project_root(path, { ".hadolint.yaml", ".hadolint.yml" }) or directory,
	}
end

local function actionlint_cwd(path)
	local git_root = project_root(path, ".git")
	if git_root then
		return git_root
	end

	local workflows_directory = parent_directory(path)
	local github_directory = workflows_directory and vim.fs.dirname(workflows_directory) or nil
	if github_directory and vim.fs.basename(github_directory) == ".github" then
		return vim.fs.dirname(github_directory)
	end
	return workflows_directory
end

local tflint_severities = {
	error = vim.diagnostic.severity.ERROR,
	warning = vim.diagnostic.severity.WARN,
	notice = vim.diagnostic.severity.INFO,
}

local function parse_tflint(output, bufnr, linter_cwd)
	local ok, decoded = pcall(vim.json.decode, output)
	if not ok or type(decoded) ~= "table" then
		return {}
	end

	local buffer_path = normalize_path(vim.api.nvim_buf_get_name(bufnr))
	local diagnostics = {}
	local issues = type(decoded.issues) == "table" and decoded.issues or {}
	for _, issue in ipairs(issues) do
		issue = type(issue) == "table" and issue or {}
		local range = type(issue.range) == "table" and issue.range or {}
		local filename = range.filename
		local start = type(range.start) == "table" and range.start or {}
		local finish = type(range["end"]) == "table" and range["end"] or {}
		if type(filename) == "string" then
			local absolute = filename:match("^/") or filename:match("^%a:[/\\]") or filename:match("^\\\\")
			local issue_path = absolute and normalize_path(filename)
				or (linter_cwd and normalize_path(vim.fs.joinpath(linter_cwd, filename)))
			if issue_path == buffer_path then
				local rule = type(issue.rule) == "table" and issue.rule or {}
				local message = type(issue.message) == "string" and issue.message or "Terraform lint issue"
				if type(rule.link) == "string" then
					message = message .. "\nReference: " .. rule.link
				end
				diagnostics[#diagnostics + 1] = {
					lnum = math.max((tonumber(start.line) or 1) - 1, 0),
					end_lnum = math.max((tonumber(finish.line) or tonumber(start.line) or 1) - 1, 0),
					col = math.max((tonumber(start.column) or 1) - 1, 0),
					end_col = math.max((tonumber(finish.column) or tonumber(start.column) or 1) - 1, 0),
					severity = tflint_severities[rule.severity] or vim.diagnostic.severity.WARN,
					source = "tflint",
					code = type(rule.name) == "string" and rule.name or nil,
					message = message,
				}
			end
		end
	end
	return diagnostics
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
		dependencies = {
			"rafamadriz/friendly-snippets",
			-- Blink captures the existing Insert-mode mapping as its fallback.
			-- Load autopairs first so an unaccepted <CR> still expands empty pairs.
			"windwp/nvim-autopairs",
		},
		opts = {
			keymap = {
				preset = "default",
				["<C-l>"] = { "show", "fallback" },
				["<C-o>"] = { "select_and_accept", "fallback" },
				["<C-y>"] = false,
				["<CR>"] = { "accept", "fallback" },
				["<Tab>"] = {
					function()
						local ok, minuet = pcall(require, "minuet.virtualtext")
						if ok and minuet.action.is_visible() then
							minuet.action.accept()
							return true
						end
					end,
					"select_next",
					"fallback",
				},
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
				window = {
					border = "rounded",
					winblend = 0,
				},
			},
		},
		opts_extend = { "sources.default" },
	},
	{
		"dnlhc/glance.nvim",
		cmd = "Glance",
		dependencies = {
			"Bekaboo/dropbar.nvim",
			"stevearc/aerial.nvim",
		},
		config = function()
			local glance = require("glance")
			local glance_config = require("glance.config")
			local default_zindex = 45
			local dropbar_winbar = "%{%v:lua.dropbar()%}"
			local method_labels = {
				definitions = "Definitions",
				implementations = "Implementations",
				type_definitions = "Type definitions",
			}
			local function active_popup_zindex()
				local ok, peek = pcall(require, "config.git_diff_peek")
				return ok and peek.child_ui_zindex() or nil
			end
			local function created_glance_windows(previous_windows)
				local list_win, preview_win
				for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
					if not previous_windows[win] and vim.api.nvim_win_get_config(win).relative ~= "" then
						local filetype = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
						if filetype == "Glance" then
							list_win = win
						else
							preview_win = win
						end
					end
				end
				return list_win, preview_win
			end
			local function allow_aerial_list_focus(list_win, preview_win)
				if glance.cleanup and glance.cleanup > 0 then
					pcall(vim.api.nvim_del_autocmd, glance.cleanup)
				end
				glance.cleanup = vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, {
					group = "Glance",
					callback = function()
						local current_win = vim.api.nvim_get_current_win()
						if current_win == list_win or current_win == preview_win then
							return
						end
						if glance.cleanup and glance.cleanup > 0 then
							vim.api.nvim_del_autocmd(glance.cleanup)
							glance.cleanup = 0
						end
						glance.actions.close()
					end,
				})
			end
			local function decorate_glance(list_win, preview_win, method, result_count)
				if not preview_win or not vim.api.nvim_win_is_valid(preview_win) then
					return
				end

				vim.w[preview_win].dotfiles_glance_preview = true
				local ok, dropbar = pcall(require, "dropbar.utils.bar")
				if ok then
					dropbar.attach(vim.api.nvim_win_get_buf(preview_win), preview_win)
					vim.wo[preview_win].winbar = dropbar_winbar
				end

				if not list_win or not vim.api.nvim_win_is_valid(list_win) then
					return
				end

				if result_count == 1 then
					local aerial_ok, aerial = pcall(require, "aerial")
					if aerial_ok then
						allow_aerial_list_focus(list_win, preview_win)
						local list_bufnr = vim.api.nvim_win_get_buf(list_win)
						vim.bo[list_bufnr].bufhidden = "hide"
						vim.w[list_win].dotfiles_glance_list_bufnr = list_bufnr
						vim.w[list_win].dotfiles_glance_aerial_layout = vim.api.nvim_win_get_config(list_win)
						vim.w[list_win].aerial_set_width = true
						aerial.open_in_win(list_win, preview_win)
						vim.wo[list_win].winbar = ""
						return
					end
				end

				local label = method_labels[method]
					or (type(method) == "string" and method:gsub("_", " "))
					or "Locations"
				vim.wo[list_win].winbar = ("%%#GlanceWinBarTitle# %s (%d)%%*"):format(label, result_count)
			end
			local function restore_glance_list(method)
				for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
					local list_bufnr = vim.w[win].dotfiles_glance_list_bufnr
					if list_bufnr and vim.api.nvim_buf_is_valid(list_bufnr) then
						vim.api.nvim_win_set_buf(win, list_bufnr)
						vim.bo[list_bufnr].bufhidden = "wipe"
						vim.w[win].dotfiles_glance_list_bufnr = nil
						vim.w[win].dotfiles_glance_aerial_layout = nil
						local label = method_labels[method]
							or (type(method) == "string" and method:gsub("_", " "))
							or "Locations"
						vim.wo[win].winbar = ("%%#GlanceWinBarTitle# %s%%*"):format(label)
					end
				end
			end
			local function focus_preview_at_current_location(previous_windows, method, result_count)
				local list_bufnr = vim.api.nvim_get_current_buf()
				local enter_preview = glance.actions.enter_win("preview")
				local list_win, preview_win = created_glance_windows(previous_windows)

				vim.schedule(function()
					if vim.api.nvim_buf_is_valid(list_bufnr) then
						-- Glance creates its preview with the target buffer, but does not
						-- apply the initial list selection until its CursorMoved handler
						-- runs. Trigger that handler before focusing the editable preview.
						vim.api.nvim_exec_autocmds("CursorMoved", {
							buffer = list_bufnr,
							modeline = false,
						})
					end
					decorate_glance(list_win, preview_win, method, result_count)
					enter_preview()
				end)
			end

			glance.setup({
				height = math.floor(36 * 1.2 + 0.5),
				zindex = default_zindex,
				border = {
					enable = true,
				},
				winbar = {
					enable = false,
				},
				hooks = {
					before_open = function(results, open, _, method)
						-- Glance builds both floats synchronously from config.options.
						-- Scope its elevated z-index to a live Git Diff Peek session;
						-- after_close restores Glance's ordinary editor default.
						glance_config.options.zindex = active_popup_zindex() or default_zindex
						local previous_windows = {}
						for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
							previous_windows[win] = true
						end
						open(results)
						focus_preview_at_current_location(previous_windows, method, #results)
					end,
					after_close = function()
						glance_config.options.zindex = default_zindex
					end,
				},
			})

			-- Glance reuses its list window for a nested lookup started inside the
			-- preview. Put the original list buffer back first so that workflow stays
			-- functional after the single-result view has shown Aerial in its place.
			local original_open = glance.actions.open
			glance.actions.open = function(method, opts)
				restore_glance_list(method)
				return original_open(method, opts)
			end
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
				underline = { severity = vim.diagnostic.severity.ERROR },
				signs = {
					severity = { min = vim.diagnostic.severity.HINT },
					-- Previous one-cell rail glyphs:
					-- [vim.diagnostic.severity.ERROR] = "󰄽"
					-- [vim.diagnostic.severity.WARN] = "󰄾"
					-- [vim.diagnostic.severity.INFO] = "+"
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
				if vim.bo[bufnr].buftype ~= "" or vim.bo[bufnr].filetype == "dockerfile" then
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

			-- Incomplete Go code commonly makes package loading fail while editing.
			-- Keep any parsed diagnostics, but do not notify about the process exit code.
			lint.linters.golangcilint.ignore_exitcode = true
			lint.linters.tflint.parser = parse_tflint

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

			local function try_lint(args)
				local bufnr = vim.api.nvim_get_current_buf()
				local path = vim.api.nvim_buf_get_name(bufnr)
				local filetype = vim.bo[bufnr].filetype
				-- Non-stdin linters cannot observe unsaved edits, so running them on
				-- InsertLeave only burns CPU while reporting stale disk contents.
				local stdin_only = args and args.event == "InsertLeave"
				if filetype == "go" then
					local options = not stdin_only and golangcilint_options(path)
					if options then
						lint.try_lint("golangcilint", options)
					end
				elseif filetype == "terraform" or filetype == "terraform-vars" then
					local options = not stdin_only and tflint_options(path)
					if options then
						lint.try_lint("tflint", options)
					end
				elseif filetype == "dockerfile" then
					local options = hadolint_options(path)
					if options then
						options.filter = stdin_only and "stdin" or nil
						lint.try_lint("hadolint", options)
					end
				else
					lint.try_lint(nil, stdin_only and { filter = "stdin" } or nil)
				end

				if filetype == "helm" then
					if not stdin_only then
						local chart_root = find_helm_chart_root(path)
						if chart_root then
							lint.try_lint("helm_lint", { cwd = chart_root })
						end
					end
					if is_helm_values_file(path) then
						lint.try_lint("yamllint", stdin_only and { filter = "stdin" } or nil)
					end
				elseif not stdin_only and filetype:match("^yaml") and is_kubernetes_buffer(bufnr) then
					lint.try_lint("kubeconform")
				end

				if path:match("/%.github/workflows/.*%.ya?ml$") then
					lint.try_lint("actionlint", {
						cwd = actionlint_cwd(path),
						filter = stdin_only and "stdin" or nil,
					})
				end
			end

			vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
				group = lint_augroup,
				callback = try_lint,
			})
		end,
	},
}
