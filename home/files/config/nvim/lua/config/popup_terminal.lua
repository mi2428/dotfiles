local M = {}

local function terminal_options()
	return {
		-- Keep this terminal independent from the managed bottom terminal, even
		-- when a count was supplied before the mapping.
		count = 1,
		win = {
			position = "float",
			relative = "editor",
			width = 0.8,
			height = 0.8,
			border = "rounded",
			title = " Terminal ",
			title_pos = "center",
			wo = {
				-- Do not inherit the tabbed bottom terminal's split-only window
				-- settings from the shared Snacks terminal configuration.
				winbar = "",
				winfixheight = false,
				winfixwidth = false,
			},
		},
	}
end

function M.toggle()
	-- Passing the shell explicitly gives Snacks a different terminal id from
	-- the nil command used by config.terminal for the bottom terminal.
	return require("snacks").terminal.toggle(vim.o.shell, terminal_options())
end

return M
