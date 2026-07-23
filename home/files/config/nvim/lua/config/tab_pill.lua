local M = {}

function M.palette()
	local colors = require("config.catppuccin").palette()

	return {
		active = colors.lavender,
		active_fg = colors.base,
		inactive = colors.surface0,
		inactive_fg = colors.text,
		dim_active = colors.surface1,
		dim_active_fg = colors.subtext0,
		dim_inactive = colors.mantle,
		dim_inactive_fg = colors.overlay1,
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

	vim.api.nvim_set_hl(0, "TerminalTabActiveDim", {
		fg = palette.dim_active_fg,
		bg = palette.dim_active,
		bold = true,
	})
	vim.api.nvim_set_hl(0, "TerminalTabActiveEdgeDim", {
		fg = palette.dim_active,
		bg = palette.fill,
	})
	vim.api.nvim_set_hl(0, "TerminalTabInactiveDim", {
		fg = palette.dim_inactive_fg,
		bg = palette.dim_inactive,
	})
	vim.api.nvim_set_hl(0, "TerminalTabInactiveEdgeDim", {
		fg = palette.dim_inactive,
		bg = palette.fill,
	})
end

return M
