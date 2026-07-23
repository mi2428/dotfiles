local function executable(name)
	return vim.fn.executable(name) == 1
end

local function preferred_cli_agent()
	if executable("codex") then
		return "codex"
	end
	if executable("claude") then
		return "claude_code"
	end
	return nil
end

local function preferred_chat_adapter()
	if executable("codex") then
		return "codex"
	end
	return "openai"
end

return {
	{
		"milanglacier/minuet-ai.nvim",
		version = "^0.9.0",
		main = "minuet",
		event = { "BufReadPre", "BufNewFile", "InsertEnter" },
		opts = {
			provider = "openai",
			n_completions = 1,
			context_window = 8000,
			throttle = 1000,
			debounce = 450,
			request_timeout = 3,
			provider_options = {
				openai = {
					model = "gpt-5.4-nano",
					-- Minuet reads the value from this environment variable.
					api_key = "OPENAI_API_KEY",
					optional = {
						max_completion_tokens = 64,
						reasoning_effort = "none",
					},
				},
			},
			virtualtext = {
				auto_trigger_ft = { "*" },
				auto_trigger_ignore_ft = {
					"codecompanion",
					"gitcommit",
					"gitrebase",
					"help",
					"lazy",
					"markdown",
					"text",
				},
				keymap = {
					-- Whole suggestions are accepted through blink.cmp's <Tab> mapping.
					accept = nil,
					accept_line = "<A-a>",
					accept_n_lines = "<A-z>",
					next = "<A-]>",
					prev = "<A-[>",
					dismiss = "<A-e>",
				},
			},
		},
		config = function(_, opts)
			require("minuet").setup(opts)

			-- If Minuet was loaded by InsertEnter, FileType has already fired. Mark
			-- existing eligible buffers so automatic virtual text can still trigger.
			for _, buf in ipairs(vim.api.nvim_list_bufs()) do
				local filetype = vim.bo[buf].filetype
				local enabled = vim.tbl_contains(opts.virtualtext.auto_trigger_ft, "*")
					or vim.tbl_contains(opts.virtualtext.auto_trigger_ft, filetype)
				local ignored = vim.tbl_contains(opts.virtualtext.auto_trigger_ignore_ft, filetype)

				if filetype ~= "" and enabled and not ignored then
					vim.b[buf].minuet_virtual_text_auto_trigger = true
				end
			end
		end,
	},
	{
		"olimorris/codecompanion.nvim",
		version = "^19.0.0",
		cmd = {
			"CodeCompanion",
			"CodeCompanionActions",
			"CodeCompanionChat",
			"CodeCompanionCLI",
			"CodeCompanionCmd",
		},
		dependencies = {
			"nvim-lua/plenary.nvim",
			"nvim-treesitter/nvim-treesitter",
			"saghen/blink.cmp",
		},
		opts = function()
			local cli_agent = preferred_cli_agent()

			return {
				adapters = {
					http = {
						openai = function()
							return require("codecompanion.adapters").extend("openai", {
								env = {
									api_key = "OPENAI_API_KEY",
								},
							})
						end,
					},
				},
				strategies = {
					chat = {
						adapter = preferred_chat_adapter(),
					},
					inline = {
						adapter = "openai",
					},
					cmd = {
						adapter = "openai",
					},
				},
				interactions = {
					cli = {
						agent = cli_agent,
						agents = {
							claude_code = {
								cmd = "claude",
								args = {},
								description = "Claude Code CLI",
							},
							codex = {
								cmd = "codex",
								args = {},
								description = "OpenAI Codex CLI",
							},
						},
						opts = {
							auto_insert = true,
							reload = true,
						},
					},
				},
				display = {
					chat = {
						show_settings = false,
					},
				},
			}
		end,
	},
}
