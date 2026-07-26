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

local function minimap_content_rows(map_win)
	local map_position = vim.api.nvim_win_get_position(map_win)
	local map_buf = vim.api.nvim_win_get_buf(map_win)
	local content_height = math.min(vim.api.nvim_buf_line_count(map_buf), vim.api.nvim_win_get_height(map_win))
	local first_row = map_position[1] + 1
	return first_row, first_row + content_height - 1, map_position
end

local function set_cursorline_mask(buf, line, column, width, repeat_linebreak)
	vim.api.nvim_buf_set_extmark(buf, cursorline_mask_namespace, line, column, {
		ephemeral = true,
		hl_mode = "replace",
		priority = 10000,
		virt_text = { { string.rep(" ", width), "MiniMapCursorLineMask" } },
		virt_text_pos = "right_align",
		virt_text_repeat_linebreak = repeat_linebreak,
	})
end

local function mask_cursorline_rows(
	buf,
	win,
	cursor,
	first_map_row,
	last_map_row,
	width,
	source_first_row,
	source_last_row
)
	local line = cursor[1] - 1
	local cursor_column = cursor[2]

	if not vim.wo[win].wrap then
		local cursor_row = vim.fn.screenpos(win, line + 1, cursor_column + 1).row
		if cursor_row >= first_map_row and cursor_row <= last_map_row then
			set_cursorline_mask(buf, line, cursor_column, width, false)
		end
		return
	end

	-- If the minimap covers the rest of this window, repeating on wrapped
	-- screen lines is exact and avoids inspecting even extremely long lines.
	if first_map_row <= source_first_row and last_map_row >= source_last_row then
		set_cursorline_mask(buf, line, 0, width, true)
		return
	end

	local text = vim.api.nvim_buf_get_lines(buf, line, line + 1, false)[1] or ""
	local is_ascii = not text:find("[\128-\255]")
	local character_count = is_ascii and #text or vim.str_utfindex(text, "utf-32")
	local cursor_character = is_ascii and cursor_column or vim.str_utfindex(text, "utf-32", cursor_column, false)
	local cursor_row = vim.fn.screenpos(win, line + 1, cursor_column + 1).row

	local function position_at(character)
		local byte_column = is_ascii and character or vim.str_byteindex(text, "utf-32", character, false)
		local screen_row = vim.fn.screenpos(win, line + 1, byte_column + 1).row
		return byte_column, screen_row
	end

	local function find_row(target_row)
		local before_cursor = target_row <= cursor_row
		local low = before_cursor and 0 or cursor_character
		local high = before_cursor and cursor_character or character_count

		while low < high do
			local middle = math.floor((low + high) / 2)
			local _, screen_row = position_at(middle)
			local position_is_before = screen_row < target_row
			if screen_row == 0 then
				position_is_before = before_cursor
			end

			if position_is_before then
				low = middle + 1
			else
				high = middle
			end
		end

		local byte_column, screen_row = position_at(low)
		if screen_row == target_row then
			return byte_column
		end
	end

	for screen_row = first_map_row, last_map_row do
		local byte_column = find_row(screen_row)
		if byte_column then
			set_cursorline_mask(buf, line, byte_column, width, false)
		end
	end
end

local function setup_cursorline_mask(map)
	vim.api.nvim_set_decoration_provider(cursorline_mask_namespace, {
		on_win = function(_, win, buf)
			local map_win = map.current.win_data[vim.api.nvim_win_get_tabpage(win)]
			if
				not vim.wo[win].cursorline
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
			if vim.api.nvim_win_get_config(win).relative ~= "" then
				return
			end

			local first_map_row, last_map_row, map_position = minimap_content_rows(map_win)
			local source_position = vim.api.nvim_win_get_position(win)
			local source_left = source_position[2] + 1
			local source_right = source_left + vim.api.nvim_win_get_width(win) - 1
			local map_width = vim.api.nvim_win_get_width(map_win)
			local map_left = map_position[2] + 1
			local map_right = map_left + map_width - 1
			local overlap = math.min(source_right, map_right) - math.max(source_left, map_left) + 1
			if overlap <= 0 then
				return
			end

			local winbar_height = vim.wo[win].winbar == "" and 0 or 1
			local source_first_row = source_position[1] + winbar_height + 1
			local source_last_row = source_position[1] + winbar_height + vim.api.nvim_win_get_height(win)
			local cursor = vim.api.nvim_win_get_cursor(win)
			mask_cursorline_rows(
				buf,
				win,
				cursor,
				first_map_row,
				last_map_row,
				overlap,
				source_first_row,
				source_last_row
			)
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
