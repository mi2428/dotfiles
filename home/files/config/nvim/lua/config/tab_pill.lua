local M = {}

function M.palette()
	local colors = require("config.catppuccin").palette()

	return {
		active = colors.lavender,
		active_fg = colors.base,
		inactive = colors.surface0,
		inactive_fg = colors.text,
		fill = "NONE",
	}
end

function M.set_terminal_highlights()
	local palette = M.palette()

	vim.api.nvim_set_hl(0, "TerminalTabFill", { bg = palette.fill })
	vim.api.nvim_set_hl(0, "TerminalTabActive", {
		fg = palette.active_fg,
		bg = palette.active,
		bold = true,
	})
	vim.api.nvim_set_hl(0, "TerminalTabActiveEdge", {
		fg = palette.active,
		bg = palette.fill,
	})
	vim.api.nvim_set_hl(0, "TerminalTabInactive", {
		fg = palette.inactive_fg,
		bg = palette.inactive,
	})
	vim.api.nvim_set_hl(0, "TerminalTabInactiveEdge", {
		fg = palette.inactive,
		bg = palette.fill,
	})
end

return M
