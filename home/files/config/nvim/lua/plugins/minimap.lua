local colors = require("config.catppuccin").palette("mocha")
local cursorline_mask_namespace = vim.api.nvim_create_namespace("dotfiles-mini-map-cursorline-mask")

local function blend(fg, bg, alpha)
	local function channel(hex, offset)
		return tonumber(hex:sub(offset, offset + 1), 16)
	end

	local values = {}
	for offset = 2, 6, 2 do
		local value = (alpha * channel(fg, offset)) + ((1 - alpha) * channel(bg, offset))
		values[#values + 1] = math.floor(value + 0.5)
	end

	return string.format("#%02x%02x%02x", values[1], values[2], values[3])
end

local function set_minimap_highlights()
	local function set(name, accent)
		vim.api.nvim_set_hl(0, name, {
			fg = accent,
			bg = blend(accent, colors.base, 0.24),
			blend = 25,
			bold = true,
		})
	end

	vim.api.nvim_set_hl(0, "MiniMapNormal", { fg = colors.text, bg = "NONE", blend = 100 })
	vim.api.nvim_set_hl(0, "MiniMapCursorLineMask", { bg = "NONE" })
	vim.api.nvim_set_hl(0, "MiniMapSearch", { fg = colors.base, bg = colors.yellow, blend = 25, bold = true })
	set("MiniMapDiagnosticError", colors.red)
	set("MiniMapDiagnosticWarn", colors.yellow)
	set("MiniMapDiagnosticInfo", colors.sky)
	set("MiniMapDiagnosticHint", colors.teal)
	set("MiniMapGitAdd", colors.green)
	set("MiniMapGitChange", colors.peach)
	set("MiniMapGitDelete", colors.red)
end

local function overlaps_minimap_content(map_win, screen_row)
	local map_position = vim.api.nvim_win_get_position(map_win)
	local map_line = screen_row - map_position[1] - 1
	local map_buf = vim.api.nvim_win_get_buf(map_win)
	return map_line >= 0 and map_line < vim.api.nvim_buf_line_count(map_buf)
end

local function setup_cursorline_mask(map)
	vim.api.nvim_set_decoration_provider(cursorline_mask_namespace, {
		on_win = function(_, win, buf, top_line, bottom_line)
			local map_win = map.current.win_data[vim.api.nvim_win_get_tabpage(win)]
			if
				not vim.wo[win].cursorline
				or buf ~= map.current.buf_data.source
				or not map_win
				or not vim.api.nvim_win_is_valid(map_win)
				or win == map_win
			then
				return
			end

			local map_config = vim.api.nvim_win_get_config(map_win)
			if map_config.anchor ~= "NE" then
				return
			end

			local window_number = vim.fn.win_id2win(win)
			local source_position = vim.fn.win_screenpos(window_number)
			local source_right = source_position[2] + vim.api.nvim_win_get_width(win) - 1
			local map_width = vim.api.nvim_win_get_width(map_win)
			local map_left = vim.o.columns - map_width + 1
			local overlap = math.min(map_width, source_right - map_left + 1)
			if overlap <= 0 then
				return
			end

			local cursor_line = vim.api.nvim_win_get_cursor(win)[1] - 1
			if cursor_line < top_line or cursor_line >= bottom_line then
				return
			end
			local cursor_position = vim.fn.screenpos(win, cursor_line + 1, 1)
			if not overlaps_minimap_content(map_win, cursor_position.row) then
				return
			end

			vim.api.nvim_buf_set_extmark(buf, cursorline_mask_namespace, cursor_line, 0, {
				ephemeral = true,
				hl_mode = "replace",
				priority = 10000,
				virt_text = { { string.rep(" ", overlap), "MiniMapCursorLineMask" } },
				virt_text_pos = "right_align",
			})
		end,
	})
end

return {
	{
		"nvim-mini/mini.map",
		version = false,
		event = { "BufReadPost", "BufNewFile" },
		keys = {
			{
				"<leader>um",
				function()
					require("mini.map").toggle()
					vim.cmd.redraw({ bang = true })
				end,
				desc = "Toggle minimap",
			},
			{
				"<leader>uM",
				function()
					require("mini.map").toggle_focus()
				end,
				desc = "Focus minimap",
			},
		},
		opts = function()
			local map = require("mini.map")

			return {
				integrations = {
					map.gen_integration.builtin_search({ search = "MiniMapSearch" }),
					map.gen_integration.diagnostic({
						error = "MiniMapDiagnosticError",
						warn = "MiniMapDiagnosticWarn",
						info = "MiniMapDiagnosticInfo",
						hint = "MiniMapDiagnosticHint",
					}),
					map.gen_integration.gitsigns({
						add = "MiniMapGitAdd",
						change = "MiniMapGitChange",
						delete = "MiniMapGitDelete",
					}),
				},
				symbols = {
					encode = map.gen_encode_symbols.dot("4x2"),
				},
				window = {
					show_integration_count = false,
					width = 12,
					winblend = 100,
				},
			}
		end,
		config = function(_, opts)
			local map = require("mini.map")

			vim.api.nvim_create_autocmd("ColorScheme", {
				group = vim.api.nvim_create_augroup("dotfiles-mini-map-colors", { clear = true }),
				pattern = "*",
				callback = set_minimap_highlights,
			})
			set_minimap_highlights()

			map.setup(opts)
			setup_cursorline_mask(map)
			map.open()
		end,
	},
}
