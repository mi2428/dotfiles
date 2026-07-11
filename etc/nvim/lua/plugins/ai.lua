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
