local colors = require("config.catppuccin").palette("mocha")
local mirror_integration_namespace = vim.api.nvim_create_namespace("dotfiles-mini-map-mirror-integrations")
local mirror_scroll_line_namespace = vim.api.nvim_create_namespace("dotfiles-mini-map-mirror-scroll-line")
local mirror_scroll_view_namespace = vim.api.nvim_create_namespace("dotfiles-mini-map-mirror-scroll-view")

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
	local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
	local normal_bg = normal.bg
	local function set(name, accent)
		vim.api.nvim_set_hl(0, name, {
			fg = accent,
			bg = blend(accent, colors.base, 0.24),
			bold = true,
		})
	end

	local function normal_attributes(attributes)
		if normal_bg ~= nil then
			attributes.bg = normal_bg
		end
		return attributes
	end
	vim.api.nvim_set_hl(0, "MiniMapNormal", normal_attributes({ fg = colors.text }))
	vim.api.nvim_set_hl(0, "MiniMapSymbolLine", normal_attributes({ fg = colors.blue, bold = true }))
	vim.api.nvim_set_hl(0, "MiniMapSymbolView", normal_attributes({ fg = colors.overlay2 }))
	vim.api.nvim_set_hl(0, "MiniMapSymbolCount", normal_attributes({ fg = colors.peach }))
	vim.api.nvim_set_hl(0, "MiniMapFocusedLine", { bg = colors.surface1 })
	vim.api.nvim_set_hl(0, "MiniMapSearch", { fg = colors.base, bg = colors.yellow, bold = true })
	set("MiniMapDiagnosticError", colors.red)
	set("MiniMapDiagnosticWarn", colors.yellow)
	set("MiniMapDiagnosticInfo", colors.sky)
	set("MiniMapDiagnosticHint", colors.teal)
	set("MiniMapGitAdd", colors.green)
	set("MiniMapGitChange", colors.peach)
	set("MiniMapGitDelete", colors.red)
end

local function style_minimap_window(win)
	if not win or not vim.api.nvim_win_is_valid(win) then
		return
	end

	vim.wo[win].winhighlight = "NormalFloat:MiniMapNormal,EndOfBuffer:MiniMapNormal,CursorLine:MiniMapFocusedLine"
end

local function is_code_window(win)
	if not win or not vim.api.nvim_win_is_valid(win) then
		return false
	end
	if vim.api.nvim_win_get_config(win).relative ~= "" and vim.w[win].dotfiles_git_diff_peek_child ~= true then
		return false
	end
	if vim.w[win].dotfiles_git_diff_peek_underlay == true then
		return false
	end

	local buf = vim.api.nvim_win_get_buf(win)
	return vim.bo[buf].buftype == "" and vim.w[win].dotfiles_disable_minimap ~= true
end

local function source_window(map)
	local current = vim.api.nvim_get_current_win()
	local tabpage = vim.api.nvim_get_current_tabpage()
	if is_code_window(current) then
		map._dotfiles_source_win = current
		return current
	end

	if
		is_code_window(map._dotfiles_source_win)
		and vim.api.nvim_win_get_tabpage(map._dotfiles_source_win) == tabpage
	then
		return map._dotfiles_source_win
	end

	local source_buf = map.current.buf_data.source
	if source_buf and vim.api.nvim_buf_is_valid(source_buf) then
		for _, win in ipairs(vim.fn.win_findbuf(source_buf)) do
			if is_code_window(win) and vim.api.nvim_win_get_tabpage(win) == tabpage then
				map._dotfiles_source_win = win
				return win
			end
		end
	end
end

local function redraw_after_geometry_change(map)
	if map._dotfiles_geometry_redraw then
		return
	end
	map._dotfiles_geometry_redraw = true
	vim.schedule(function()
		map._dotfiles_geometry_redraw = false
		vim.cmd.redraw({ bang = true })
	end)
end

local function window_text_position(win)
	local position = vim.api.nvim_win_get_position(win)
	local config = vim.api.nvim_win_get_config(win)
	local border = config.border
	if type(border) == "string" then
		if border ~= "" and border ~= "none" then
			return { position[1] + 1, position[2] + 1 }
		end
		return position
	end
	if type(border) ~= "table" then
		return position
	end

	local function occupied(...)
		for _, index in ipairs({ ... }) do
			local cell = border[index]
			if type(cell) == "table" then
				cell = cell[1]
			end
			if type(cell) == "string" and vim.fn.strdisplaywidth(cell) > 0 then
				return 1
			end
		end
		return 0
	end

	return {
		position[1] + occupied(1, 2, 3),
		position[2] + occupied(1, 7, 8),
	}
end

local function update_minimap_geometry(map)
	local map_win = map.current.win_data[vim.api.nvim_get_current_tabpage()]
	if not map_win or not vim.api.nvim_win_is_valid(map_win) then
		return false
	end
	style_minimap_window(map_win)

	local config = vim.api.nvim_win_get_config(map_win)
	if config.relative ~= "editor" or config.anchor ~= "NE" then
		return false
	end

	local source_win = source_window(map)
	if not source_win then
		return false
	end

	local position = window_text_position(source_win)
	local source_config = vim.api.nvim_win_get_config(source_win)
	local row = position[1]
	local col = position[2] + vim.api.nvim_win_get_width(source_win)
	local height = vim.api.nvim_win_get_height(source_win)
	local configured_width = ((map.current.opts or {}).window or {}).width
		or ((map.config or {}).window or {}).width
		or config.width
	local configured_zindex = ((map.current.opts or {}).window or {}).zindex
		or ((map.config or {}).window or {}).zindex
		or config.zindex
	local width = math.min(configured_width, vim.api.nvim_win_get_width(source_win))
	local zindex = math.max(configured_zindex or 0, (source_config.zindex or 0) + 1)
	if
		config.row == row
		and config.col == col
		and config.width == width
		and config.height == height
		and config.zindex == zindex
		and config.hide
	then
		return false
	end

	vim.api.nvim_win_set_config(map_win, {
		relative = "editor",
		anchor = "NE",
		row = row,
		col = col,
		width = width,
		height = height,
		hide = true,
		focusable = config.focusable,
		zindex = zindex,
	})
	redraw_after_geometry_change(map)
	return true
end

local function setup_code_layout(map)
	if map._dotfiles_code_layout then
		return
	end
	map._dotfiles_code_layout = true

	local manager = {
		active_source = nil,
		detached_source_margins = {},
		enabled = false,
		focused = false,
		managing_options = 0,
		managing_windows = 0,
		mirrors = {},
		pending = {},
		rendered_maps = {},
		scheduled = false,
		source_buf = nil,
		source_margins = {},
		wrap_margins = {},
	}
	map._dotfiles_multi_window_manager = manager

	local function options()
		if map.current.opts and next(map.current.opts) then
			return map.current.opts
		end
		return map.config or {}
	end

	local function native_geometry()
		local win = map.current.win_data[vim.api.nvim_get_current_tabpage()]
		if not win or not vim.api.nvim_win_is_valid(win) then
			return nil
		end
		local config = vim.api.nvim_win_get_config(win)
		return config.row, config.col, config.width, config.height, config.zindex, config.hide
	end

	local function scrollbar_offset(opts)
		local symbols = opts.symbols or {}
		local offset = math.max(
			vim.fn.strdisplaywidth(symbols.scroll_line or ""),
			vim.fn.strdisplaywidth(symbols.scroll_view or "")
		)
		return offset + ((opts.window or {}).show_integration_count and 1 or 0)
	end

	local function manage_windows(callback)
		manager.managing_windows = manager.managing_windows + 1
		local ok, result = xpcall(callback, debug.traceback)
		manager.managing_windows = manager.managing_windows - 1
		if not ok then
			error(result, 0)
		end
		return result
	end

	local function get_local_sidescrolloff(win)
		return vim.api.nvim_get_option_value("sidescrolloff", { scope = "local", win = win })
	end

	local function set_local_sidescrolloff(win, value)
		manager.managing_options = manager.managing_options + 1
		local ok, err = pcall(vim.api.nvim_set_option_value, "sidescrolloff", value, {
			scope = "local",
			win = win,
		})
		manager.managing_options = manager.managing_options - 1
		if not ok then
			error(err, 0)
		end
	end

	local function restore_source_margin(win)
		local state = manager.source_margins[win]
		if not state then
			return
		end
		manager.source_margins[win] = nil
		if not vim.api.nvim_win_is_valid(win) then
			return
		end

		-- Preserve an option value changed by the user after our last layout pass.
		-- Otherwise restore -1 as -1 so a previously inherited global value keeps
		-- following future global changes after the minimap closes.
		if get_local_sidescrolloff(win) == state.applied then
			set_local_sidescrolloff(win, state.restore_local)
		end
	end

	local function restore_all_source_margins()
		for win in pairs(vim.deepcopy(manager.source_margins)) do
			restore_source_margin(win)
		end
	end

	local function inherit_source_margin(win, parent)
		if not manager.enabled or manager.source_margins[win] or not is_code_window(win) then
			return false
		end
		parent = parent or vim.fn.win_getid(vim.fn.winnr("#"))
		local parent_state = manager.source_margins[parent]
		local detached_restore = manager.detached_source_margins[parent]
		if not parent_state and detached_restore == nil then
			return false
		end

		-- Splits copy window-local options. Remember the parent's unreserved value
		-- before the copied, already-adjusted value can be mistaken for user intent.
		manager.source_margins[win] = {
			applied = get_local_sidescrolloff(win),
			restore_local = parent_state and parent_state.restore_local or detached_restore,
		}
		manager.detached_source_margins[parent] = nil
		return true
	end

	function manager.inherit_source_margin(child, parent)
		if not vim.api.nvim_win_is_valid(child) or not vim.api.nvim_win_is_valid(parent) or child == parent then
			return false
		end
		return inherit_source_margin(child, parent)
	end

	function manager.prepare_source_margin_transfer(parent)
		if not manager.enabled or not vim.api.nvim_win_is_valid(parent) then
			return false
		end
		local state = manager.source_margins[parent]
		if not state then
			return false
		end
		local current = get_local_sidescrolloff(parent)
		if state.applied ~= nil and current ~= state.applied then
			state.restore_local = current
		end
		manager.detached_source_margins[parent] = state.restore_local
		restore_source_margin(parent)
		return true
	end

	function manager.discard_source_margin_transfer(parent)
		if type(parent) ~= "number" or manager.detached_source_margins[parent] == nil then
			return false
		end
		manager.detached_source_margins[parent] = nil
		return true
	end

	local function reserve_source_margin(source_win, map_win)
		if not is_code_window(source_win) or not map_win or not vim.api.nvim_win_is_valid(map_win) then
			return false
		end
		local map_width = vim.api.nvim_win_get_width(map_win)
		if map_width * 2 > vim.api.nvim_win_get_width(source_win) then
			-- 'sidescrolloff' is symmetric and centers the cursor when its value is
			-- too large. It cannot keep the cursor left of a map occupying more than
			-- half the pane, so leave that pre-existing narrow-pane case untouched.
			restore_source_margin(source_win)
			return false
		end

		local current = get_local_sidescrolloff(source_win)
		local state = manager.source_margins[source_win]
		if not state then
			state = { restore_local = manager.detached_source_margins[source_win] or current }
			manager.source_margins[source_win] = state
			manager.detached_source_margins[source_win] = nil
		elseif state.applied ~= nil and current ~= state.applied then
			-- Treat an intervening :setlocal as the new base instead of fighting it.
			state.restore_local = current
		end

		local base = state.restore_local
		if base < 0 then
			base = vim.api.nvim_get_option_value("sidescrolloff", { scope = "global" })
		end
		local wanted = base + map_width
		if current ~= wanted then
			set_local_sidescrolloff(source_win, wanted)
		end
		state.applied = wanted
		return current ~= wanted
	end

	local function sync_source_margins()
		local wanted = {}
		local native = map.current.win_data[vim.api.nvim_get_current_tabpage()]
		if native and vim.api.nvim_win_is_valid(native) and is_code_window(manager.active_source) then
			wanted[manager.active_source] = true
			reserve_source_margin(manager.active_source, native)
		end
		for _, instance in pairs(manager.mirrors) do
			if vim.api.nvim_win_is_valid(instance.win) and is_code_window(instance.source_win) then
				wanted[instance.source_win] = true
				reserve_source_margin(instance.source_win, instance.win)
			end
		end
		for win in pairs(vim.deepcopy(manager.source_margins)) do
			if not wanted[win] then
				restore_source_margin(win)
			end
		end
	end

	local function clear_wrap_margin(win)
		local state = manager.wrap_margins[win]
		if not state then
			return
		end
		manager.wrap_margins[win] = nil
		if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
			pcall(vim.api.nvim_buf_clear_namespace, state.buf, state.namespace, 0, -1)
		end
	end

	local function clear_all_wrap_margins()
		for win in pairs(vim.deepcopy(manager.wrap_margins)) do
			clear_wrap_margin(win)
		end
	end

	local function add_wrap_padding(source_win, buf, namespace, row, segment, text_width, map_width)
		local line = row + 1
		local screen_row_end = (segment + 1) * text_width
		local padding_start = screen_row_end - map_width + 1
		local line_end = vim.fn.virtcol({ line, "$" }, false, source_win)
		if line_end <= padding_start then
			return false
		end

		local byte_col = vim.fn.virtcol2col(source_win, line, padding_start)
		if byte_col <= 0 then
			return false
		end
		local character_range = vim.fn.virtcol({ line, byte_col }, true, source_win)
		local padding_width = screen_row_end - character_range[1] + 1
		if padding_width <= 0 then
			return false
		end
		vim.api.nvim_buf_set_extmark(buf, namespace, row, byte_col - 1, {
			-- No highlight is intentional: cells outside the float (for example when
			-- a tab straddles the boundary) retain the source row's own background.
			virt_text = { { string.rep(" ", padding_width) } },
			virt_text_pos = "inline",
			right_gravity = false,
		})
		return true
	end

	local function reserve_wrap_margin(source_win, map_win)
		if
			not is_code_window(source_win)
			or not vim.wo[source_win].wrap
			or vim.wo[source_win].linebreak
			or vim.wo[source_win].showbreak ~= ""
			or not map_win
			or not vim.api.nvim_win_is_valid(map_win)
		then
			-- Neovim 0.12 can crash while resolving virtual columns when inline
			-- virtual text is combined with linebreak or showbreak. Those opt-in
			-- modes stay on native wrapping until that core interaction is safe.
			clear_wrap_margin(source_win)
			return
		end
		local win_info = vim.fn.getwininfo(source_win)[1]
		local map_width = vim.api.nvim_win_get_width(map_win)
		local text_width = win_info and win_info.width - win_info.textoff or 0
		if text_width <= map_width then
			clear_wrap_margin(source_win)
			return
		end

		local map_buf = vim.api.nvim_win_get_buf(map_win)
		local map_height = math.min(vim.api.nvim_buf_line_count(map_buf), vim.api.nvim_win_get_height(source_win))
		if map_height <= 0 then
			clear_wrap_margin(source_win)
			return
		end

		local buf = vim.api.nvim_win_get_buf(source_win)
		local view = vim.api.nvim_win_call(source_win, vim.fn.winsaveview)
		if view.skipcol > 0 then
			-- Replacing inline virtual text while Neovim is vertically scrolled inside
			-- one very long wrapped line can crash 0.12. Re-enable the margin when the
			-- view returns to a logical-line boundary (skipcol == 0).
			clear_wrap_margin(source_win)
			return
		end
		local state = manager.wrap_margins[source_win]
		if not state then
			state = { namespace = vim.api.nvim_create_namespace("") }
			manager.wrap_margins[source_win] = state
			-- Inline virtual text is buffer-owned by default. Restrict this anonymous
			-- namespace to its source window so differently sized views of the same
			-- buffer can reserve independent wrap widths.
			vim.api.nvim__ns_set(state.namespace, { wins = { source_win } })
		elseif state.buf and state.buf ~= buf and vim.api.nvim_buf_is_valid(state.buf) then
			vim.api.nvim_buf_clear_namespace(state.buf, state.namespace, 0, -1)
		end
		vim.api.nvim_buf_clear_namespace(buf, state.namespace, 0, -1)
		state.buf = buf

		-- Neovim has no right-side wrap margin. Fill only the screen-row suffixes
		-- covered by the minimap with window-scoped inline virtual spaces. Because
		-- the padding stops at the encoded map EOF, later rows still use the full
		-- editor width. virtcol2col() keeps boundaries correct for tabs, wide glyphs,
		-- and breakindent.
		local top_row = view.topline - 1
		local line_count = vim.api.nvim_buf_line_count(buf)
		local row = top_row
		while row < line_count do
			local rows_before = 0
			if row > top_row then
				rows_before = vim.api.nvim_win_text_height(source_win, {
					start_row = top_row,
					start_vcol = view.skipcol,
					end_row = row,
					end_vcol = 0,
					max_height = map_height + 1,
				}).all
			end
			if rows_before >= map_height then
				break
			end

			local fold_end = vim.api.nvim_win_call(source_win, function()
				return vim.fn.foldclosedend(row + 1)
			end)
			if fold_end >= row + 1 then
				row = fold_end
			else
				local first_segment = row == top_row and math.floor(view.skipcol / text_width) or 0
				for offset = 0, map_height - rows_before - 1 do
					if
						not add_wrap_padding(
							source_win,
							buf,
							state.namespace,
							row,
							first_segment + offset,
							text_width,
							map_width
						)
					then
						break
					end
				end
				row = row + 1
			end
		end
	end

	local function sync_wrap_margins()
		local wanted = {}
		local native = map.current.win_data[vim.api.nvim_get_current_tabpage()]
		if native and vim.api.nvim_win_is_valid(native) and is_code_window(manager.active_source) then
			wanted[manager.active_source] = true
			reserve_wrap_margin(manager.active_source, native)
		end
		for _, instance in pairs(manager.mirrors) do
			if vim.api.nvim_win_is_valid(instance.win) and is_code_window(instance.source_win) then
				wanted[instance.source_win] = true
				reserve_wrap_margin(instance.source_win, instance.win)
			end
		end
		for win in pairs(vim.deepcopy(manager.wrap_margins)) do
			if not wanted[win] then
				clear_wrap_margin(win)
			end
		end
	end

	local function source_to_map_line(instance, source_line)
		local data = instance.encode_data
		if not data or data.source_rows == 0 or data.map_rows == 0 then
			return 1
		end

		local coefficient = data.rescaled_rows / data.source_rows
		local rescaled_row = math.floor(coefficient * (source_line - 1)) + 1
		local map_line = math.floor((rescaled_row - 1) / data.resolution_row) + 1
		return math.min(math.max(map_line, 1), data.map_rows)
	end

	local function close_mirror(source_win)
		local instance = manager.mirrors[source_win]
		if not instance then
			return
		end
		manager.mirrors[source_win] = nil
		local display = manager.rendered_maps[instance.win]
		manager.rendered_maps[instance.win] = nil
		manage_windows(function()
			if display and vim.api.nvim_win_is_valid(display.win) then
				pcall(vim.api.nvim_win_close, display.win, true)
			end
			if vim.api.nvim_win_is_valid(instance.win) then
				pcall(vim.api.nvim_win_close, instance.win, true)
			end
			if vim.api.nvim_buf_is_valid(instance.buf) then
				pcall(vim.api.nvim_buf_delete, instance.buf, { force = true })
			end
		end)
	end

	function manager.close_all()
		restore_all_source_margins()
		manager.detached_source_margins = {}
		clear_all_wrap_margins()
		for map_win, display in pairs(manager.rendered_maps) do
			manager.rendered_maps[map_win] = nil
			manage_windows(function()
				if vim.api.nvim_win_is_valid(display.win) then
					pcall(vim.api.nvim_win_close, display.win, true)
				end
			end)
		end
		for source_win in pairs(vim.deepcopy(manager.mirrors)) do
			close_mirror(source_win)
		end
		manager.active_source = nil
		manager.focused = false
		manager.source_buf = nil
	end

	-- Native and mirror floats own mini.map state and encoding only. They remain
	-- hidden; visible minimaps are created exclusively by `render_map()` below.
	local function mirror_geometry(source_win, width)
		local position = window_text_position(source_win)
		width = math.min(width, vim.api.nvim_win_get_width(source_win))
		return {
			relative = "editor",
			anchor = "NE",
			row = position[1],
			col = position[2] + vim.api.nvim_win_get_width(source_win),
			width = width,
			height = vim.api.nvim_win_get_height(source_win),
			hide = true,
			focusable = false,
			style = "minimal",
			zindex = (options().window or {}).zindex or 10,
		}
	end

	local function create_mirror(source_win)
		local opts = options()
		local window_opts = opts.window or {}
		local buf = vim.api.nvim_create_buf(false, true)
		vim.bo[buf].bufhidden = "wipe"
		vim.bo[buf].buftype = "nofile"
		vim.bo[buf].filetype = "minimap"
		vim.bo[buf].swapfile = false

		local win = manage_windows(function()
			return vim.api.nvim_open_win(buf, false, mirror_geometry(source_win, window_opts.width or 10))
		end)
		vim.wo[win].winblend = window_opts.winblend or 0
		style_minimap_window(win)
		vim.wo[win].wrap = false

		local instance = { buf = buf, win = win, source_win = source_win }
		manager.mirrors[source_win] = instance
		return instance
	end

	local function update_mirror_geometry(instance)
		if not vim.api.nvim_win_is_valid(instance.win) then
			return { geometry = false, size = false }
		end

		local current = vim.api.nvim_win_get_config(instance.win)
		local wanted = mirror_geometry(instance.source_win, (options().window or {}).width or current.width)
		local size_changed = current.width ~= wanted.width or current.height ~= wanted.height
		local changed = current.row ~= wanted.row
			or current.col ~= wanted.col
			or size_changed
			or current.zindex ~= wanted.zindex
		if changed then
			vim.api.nvim_win_set_config(instance.win, wanted)
		end
		return { geometry = changed, size = size_changed }
	end

	local function close_rendered_map(map_win)
		local display = manager.rendered_maps[map_win]
		if not display then
			return
		end
		manager.rendered_maps[map_win] = nil
		manage_windows(function()
			if vim.api.nvim_win_is_valid(display.win) then
				pcall(vim.api.nvim_win_close, display.win, true)
			end
		end)
	end

	local function render_map(source_win, map_win)
		if not is_code_window(source_win) or not vim.api.nvim_win_is_valid(map_win) then
			return
		end
		-- One cropped-height, full-width display float is the sole renderer. Each
		-- encoded row owns the complete interval from rail through pane edge; rows
		-- below this buffer's EOF deliberately remain editor-owned.
		local map_buf = vim.api.nvim_win_get_buf(map_win)
		local source_position = window_text_position(source_win)
		local map_width = vim.api.nvim_win_get_width(map_win)
		local map_left = source_position[2] + vim.api.nvim_win_get_width(source_win) - map_width
		local map_config = vim.api.nvim_win_get_config(map_win)
		local native = map.current.win_data[vim.api.nvim_get_current_tabpage()]
		local focused_line = manager.focused and map_win == native and vim.api.nvim_win_get_cursor(map_win)[1] - 1
			or nil
		local height = math.min(vim.api.nvim_buf_line_count(map_buf), vim.api.nvim_win_get_height(source_win))
		if height == 0 then
			close_rendered_map(map_win)
			return
		end
		local geometry = {
			relative = "editor",
			anchor = "NW",
			row = source_position[1],
			col = map_left,
			width = map_width,
			height = height,
			focusable = false,
			style = "minimal",
			zindex = map_config.zindex,
		}
		local display = manager.rendered_maps[map_win]
		if not display or not vim.api.nvim_win_is_valid(display.win) then
			local win = manage_windows(function()
				return vim.api.nvim_open_win(map_buf, false, geometry)
			end)
			display = { win = win }
			manager.rendered_maps[map_win] = display
			vim.wo[win].winblend = (options().window or {}).winblend or 0
			vim.wo[win].scrolloff = 0
			vim.wo[win].wrap = false
			style_minimap_window(win)
		else
			local current = vim.api.nvim_win_get_config(display.win)
			if
				current.row ~= geometry.row
				or current.col ~= geometry.col
				or current.width ~= geometry.width
				or current.height ~= geometry.height
				or current.zindex ~= geometry.zindex
			then
				vim.api.nvim_win_set_config(display.win, geometry)
			end
		end
		vim.api.nvim_win_call(display.win, function()
			vim.fn.winrestview({ topline = 1, leftcol = 0 })
		end)
		if focused_line then
			vim.api.nvim_win_set_cursor(display.win, { focused_line + 1, 0 })
		end
		vim.wo[display.win].cursorline = focused_line ~= nil
	end

	local function render_all_maps()
		local wanted = {}
		local native = map.current.win_data[vim.api.nvim_get_current_tabpage()]
		if native and vim.api.nvim_win_is_valid(native) and is_code_window(manager.active_source) then
			wanted[native] = true
			render_map(manager.active_source, native)
		end
		for _, instance in pairs(manager.mirrors) do
			if vim.api.nvim_win_is_valid(instance.win) then
				wanted[instance.win] = true
				render_map(instance.source_win, instance.win)
			end
		end
		for map_win in pairs(manager.rendered_maps) do
			if not wanted[map_win] then
				close_rendered_map(map_win)
			end
		end
	end

	local function sync_focused_display()
		-- Keep the full-height state float hidden even while focused: revealing it
		-- would obscure editor cells below the encoded EOF. Mirror its cursor into
		-- the visible display instead.
		local native = map.current.win_data[vim.api.nvim_get_current_tabpage()]
		local display = native and manager.rendered_maps[native]
		if not native or not display or not vim.api.nvim_win_is_valid(display.win) then
			return
		end
		if manager.focused then
			vim.api.nvim_win_set_cursor(display.win, vim.api.nvim_win_get_cursor(native))
		end
		vim.wo[display.win].cursorline = manager.focused
	end

	local function is_inactive_mirror_placeholder(win, active_source)
		if win == active_source or not vim.api.nvim_win_is_valid(win) then
			return false
		end
		local buf = vim.api.nvim_win_get_buf(win)
		return vim.bo[buf].buftype == ""
			and vim.api.nvim_buf_get_name(buf) == ""
			and not vim.bo[buf].modified
			and vim.api.nvim_buf_line_count(buf) == 1
			and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ""
	end

	local function reconcile_mirrors()
		local changes = { structure = false, geometry = false, size = false }
		local official_win = map.current.win_data[vim.api.nvim_get_current_tabpage()]
		if not official_win or not vim.api.nvim_win_is_valid(official_win) then
			if not manager.enabled then
				manager.close_all()
				return changes
			end

			-- Commands such as `:only` close floating windows together with ordinary
			-- splits, without going through MiniMap.close(). Reopen the native map
			-- while keeping an explicit user toggle-off authoritative.
			local source_win = source_window(map)
			if not source_win then
				manager.close_all()
				return changes
			end
			local previous_win = vim.api.nvim_get_current_win()
			if previous_win ~= source_win then
				vim.api.nvim_set_current_win(source_win)
			end
			map.open()
			official_win = map.current.win_data[vim.api.nvim_get_current_tabpage()]
			if previous_win ~= source_win then
				vim.schedule(function()
					vim.schedule(function()
						if vim.api.nvim_win_is_valid(previous_win) then
							vim.api.nvim_set_current_win(previous_win)
						end
					end)
				end)
			end
			if not official_win or not vim.api.nvim_win_is_valid(official_win) then
				manager.close_all()
				return changes
			end
			changes.structure = true
		end

		local active_source = source_window(map)
		if not active_source then
			manager.close_all()
			return changes
		end
		local source_buf = vim.api.nvim_win_get_buf(active_source)
		local previous_active = manager.active_source
		if
			previous_active
			and previous_active ~= active_source
			and manager.source_buf == source_buf
			and is_code_window(previous_active)
			and vim.api.nvim_win_get_buf(previous_active) == source_buf
			and manager.mirrors[active_source]
		then
			-- Focus changes between views of the same buffer should only exchange
			-- ownership with the native map. Reuse the mirror buffer so ordinary
			-- window navigation does not encode the whole source again.
			local instance = manager.mirrors[active_source]
			manager.mirrors[active_source] = nil
			instance.source_win = previous_active
			instance.view = nil
			instance.cursor_line = nil
			manager.mirrors[previous_active] = instance
		end
		manager.active_source = active_source
		manager.source_buf = source_buf

		local wanted = {}
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			if
				win ~= active_source
				and is_code_window(win)
				and not is_inactive_mirror_placeholder(win, active_source)
			then
				wanted[win] = true
			end
		end

		for win in pairs(vim.deepcopy(manager.mirrors)) do
			if not wanted[win] or not is_code_window(win) then
				close_mirror(win)
				changes.structure = true
			end
		end

		for win in pairs(wanted) do
			local instance = manager.mirrors[win]
			if not instance or not vim.api.nvim_win_is_valid(instance.win) then
				if instance then
					close_mirror(win)
				end
				instance = create_mirror(win)
				changes.structure = true
			end
			local geometry = update_mirror_geometry(instance)
			changes.geometry = changes.geometry or geometry.geometry
			changes.size = changes.size or geometry.size
		end
		sync_source_margins()

		return changes
	end

	local function refresh_mirror_lines(instance)
		if not is_code_window(instance.source_win) or not vim.api.nvim_buf_is_valid(instance.buf) then
			return
		end

		local opts = options()
		local symbols = opts.symbols or {}
		local encode_symbols = symbols.encode
		if not encode_symbols or not encode_symbols.resolution then
			return
		end

		local source_buf = vim.api.nvim_win_get_buf(instance.source_win)
		local source_lines = vim.api.nvim_buf_get_lines(source_buf, 0, -1, true)
		if #source_lines == 0 then
			return
		end

		local offset = scrollbar_offset(opts)
		local n_rows = vim.api.nvim_win_get_height(instance.win)
		local n_cols = vim.api.nvim_win_get_width(instance.win) - offset
		local prefix = string.rep(" ", offset)
		local encoded_lines
		local rescaled_rows
		local resolution_row
		local copied_native = false
		if n_cols <= 0 then
			encoded_lines = {}
			for _ = 1, n_rows do
				encoded_lines[#encoded_lines + 1] = prefix
			end
			rescaled_rows = n_rows
			resolution_row = 1
		else
			resolution_row = encode_symbols.resolution.row
			rescaled_rows = math.min(#source_lines, n_rows * resolution_row)
			local expected_rows = math.ceil(rescaled_rows / resolution_row)
			local native_win = map.current.win_data[vim.api.nvim_get_current_tabpage()]
			local native_buf = map.current.buf_data.map
			if
				native_win
				and vim.api.nvim_win_is_valid(native_win)
				and native_buf
				and vim.api.nvim_buf_is_valid(native_buf)
				and map.current.buf_data.source == source_buf
				and vim.api.nvim_win_get_width(native_win) == vim.api.nvim_win_get_width(instance.win)
				and vim.api.nvim_win_get_height(native_win) == n_rows
				and vim.api.nvim_buf_line_count(native_buf) == expected_rows
			then
				-- The native instance has just encoded this same buffer. Equal-sized
				-- split maps can copy those rows instead of scanning the source again.
				encoded_lines = vim.api.nvim_buf_get_lines(native_buf, 0, -1, true)
				copied_native = true
			else
				encoded_lines = map.encode_strings(source_lines, {
					n_cols = n_cols,
					n_rows = n_rows,
					symbols = encode_symbols,
				})
				encoded_lines = vim.tbl_map(function(line)
					return prefix .. line
				end, encoded_lines)
			end
		end
		vim.api.nvim_buf_set_lines(instance.buf, 0, -1, true, encoded_lines)
		instance.encode_data = {
			source_rows = #source_lines,
			rescaled_rows = rescaled_rows,
			resolution_row = resolution_row,
			map_rows = #encoded_lines,
			offset = offset,
		}
		instance.copied_native = copied_native
		instance.view = nil
		instance.cursor_line = nil
	end

	local function refresh_mirror_integrations(instance)
		if not instance.encode_data or not vim.api.nvim_buf_is_valid(instance.buf) then
			return
		end
		vim.api.nvim_buf_clear_namespace(instance.buf, mirror_integration_namespace, 0, -1)
		if instance.copied_native then
			local native_namespace = vim.api.nvim_get_namespaces().MiniMapIntegrations
			local native_buf = map.current.buf_data.map
			if native_namespace and native_buf and vim.api.nvim_buf_is_valid(native_buf) then
				for _, mark in
					ipairs(vim.api.nvim_buf_get_extmarks(native_buf, native_namespace, 0, -1, { details = true }))
				do
					local details = mark[4]
					pcall(vim.api.nvim_buf_set_extmark, instance.buf, mirror_integration_namespace, mark[2], mark[3], {
						hl_group = details.hl_group,
						end_row = details.end_row,
						end_col = details.end_col,
						strict = false,
					})
				end
				return
			end
		end

		local seen = {}
		for _, integration in ipairs(options().integrations or {}) do
			-- mini.map's built-in diagnostic, search, and gitsigns integrations
			-- read `current.buf_data.source`. Point it at this mirror only for the
			-- duration of the synchronous integration call, then restore the native
			-- map's source before any scheduled work can observe it.
			local native_source = map.current.buf_data.source
			map.current.buf_data.source = vim.api.nvim_win_get_buf(instance.source_win)
			local ok, highlights = pcall(vim.api.nvim_win_call, instance.source_win, integration)
			map.current.buf_data.source = native_source
			if ok then
				for _, highlight in ipairs(highlights or {}) do
					local line = source_to_map_line(instance, highlight.line) - 1
					if not seen[line] then
						seen[line] = true
						pcall(
							vim.api.nvim_buf_set_extmark,
							instance.buf,
							mirror_integration_namespace,
							line,
							instance.encode_data.offset,
							{
								hl_group = highlight.hl_group,
								end_row = line + 1,
								end_col = 0,
								strict = false,
							}
						)
					end
				end
			end
		end
	end

	local function refresh_mirror_scrollbar(instance)
		if not instance.encode_data or not is_code_window(instance.source_win) then
			return
		end

		local view = vim.api.nvim_win_call(instance.source_win, function()
			return { from_line = vim.fn.line("w0"), to_line = vim.fn.line("w$") }
		end)
		local cursor_line = vim.api.nvim_win_get_cursor(instance.source_win)[1]
		local symbols = options().symbols or {}

		if not instance.view or instance.view.from_line ~= view.from_line or instance.view.to_line ~= view.to_line then
			vim.api.nvim_buf_clear_namespace(instance.buf, mirror_scroll_view_namespace, 0, -1)
			local first = source_to_map_line(instance, view.from_line)
			local last = source_to_map_line(instance, view.to_line)
			for line = first, last do
				pcall(vim.api.nvim_buf_set_extmark, instance.buf, mirror_scroll_view_namespace, line - 1, 0, {
					virt_text = { { symbols.scroll_view or "", "MiniMapSymbolView" } },
					virt_text_pos = "overlay",
					priority = 10,
				})
			end
			instance.view = view
		end

		if instance.cursor_line ~= cursor_line then
			vim.api.nvim_buf_clear_namespace(instance.buf, mirror_scroll_line_namespace, 0, -1)
			local line = source_to_map_line(instance, cursor_line)
			pcall(vim.api.nvim_buf_set_extmark, instance.buf, mirror_scroll_line_namespace, line - 1, 0, {
				virt_text = { { symbols.scroll_line or "", "MiniMapSymbolLine" } },
				virt_text_pos = "overlay",
				priority = 11,
			})
			instance.cursor_line = cursor_line
		end
	end

	function manager.refresh_scrollbars()
		for _, instance in pairs(manager.mirrors) do
			refresh_mirror_scrollbar(instance)
		end
	end

	function manager.refresh_content()
		for _, instance in pairs(manager.mirrors) do
			refresh_mirror_lines(instance)
			refresh_mirror_integrations(instance)
			refresh_mirror_scrollbar(instance)
		end
	end

	local function flush()
		manager.scheduled = false
		local parts = manager.pending
		manager.pending = {}
		local changes = { structure = false, geometry = false, size = false }
		if parts.layout then
			changes.geometry = update_minimap_geometry(map)
		end
		if parts.layout or parts.lines then
			local reconciled = reconcile_mirrors()
			changes.structure = reconciled.structure
			changes.geometry = changes.geometry or reconciled.geometry
			changes.size = reconciled.size
		end
		if changes.structure or changes.size then
			parts.lines = true
			parts.integrations = true
			parts.scrollbar = true
		end

		for _, instance in pairs(manager.mirrors) do
			if parts.lines then
				refresh_mirror_lines(instance)
			end
			if parts.integrations then
				refresh_mirror_integrations(instance)
			end
			if parts.scrollbar or parts.lines then
				refresh_mirror_scrollbar(instance)
			end
		end
		if parts.display or parts.lines or changes.structure or changes.geometry then
			render_all_maps()
		end
		if parts.wrap or parts.lines or changes.structure or changes.geometry then
			sync_wrap_margins()
		end
		if parts.focus then
			sync_focused_display()
		end
	end

	function manager.schedule(parts)
		for name, enabled in pairs(parts or {}) do
			manager.pending[name] = manager.pending[name] or enabled
		end
		if manager.scheduled then
			return
		end
		manager.scheduled = true
		vim.schedule(flush)
	end

	function manager.map_window_for_source(win)
		if win == map._dotfiles_source_win then
			return map.current.win_data[vim.api.nvim_win_get_tabpage(win)]
		end
		local instance = manager.mirrors[win]
		return instance and instance.win or nil
	end

	local original_refresh = map.refresh
	map.refresh = function(opts, parts)
		local source_win = source_window(map)
		local ownership_changed = source_win and source_win ~= manager.active_source
		local corrected_geometry = update_minimap_geometry(map)
		local before_row, before_col, before_width, before_height, before_zindex, before_hide = native_geometry()
		local result = original_refresh(opts, parts)
		-- mini.map first restores its editor-height defaults and only then queues
		-- content encoding. Constrain the float synchronously so encoding observes
		-- the code window's actual text height.
		update_minimap_geometry(map)
		local after_row, after_col, after_width, after_height, after_zindex, after_hide = native_geometry()
		local normalized =
			vim.tbl_deep_extend("force", { integrations = true, lines = true, scrollbar = true }, parts or {})
		local size_changed = before_width ~= after_width or before_height ~= after_height
		if size_changed and not normalized.lines then
			original_refresh(map.current.opts, { integrations = true, lines = true, scrollbar = true })
			update_minimap_geometry(map)
			normalized.lines = true
			normalized.integrations = true
			normalized.scrollbar = true
		end
		local display_changed = corrected_geometry
			or before_row ~= after_row
			or before_col ~= after_col
			or before_width ~= after_width
			or before_height ~= after_height
			or before_zindex ~= after_zindex
			or before_hide ~= after_hide
			or ownership_changed
		if display_changed then
			normalized.layout = true
			normalized.display = true
		end
		manager.schedule(normalized)
		return result
	end

	local original_open = map.open
	map.open = function(...)
		manager.enabled = true
		local args = { ... }
		return manage_windows(function()
			return original_open(unpack(args))
		end)
	end

	if map.toggle_focus then
		local original_toggle_focus = map.toggle_focus
		map.toggle_focus = function(...)
			local native = map.current.win_data[vim.api.nvim_get_current_tabpage()]
			local entering = native and vim.api.nvim_win_is_valid(native) and vim.api.nvim_get_current_win() ~= native
			if entering then
				manager.focused = true
			end
			local result = original_toggle_focus(...)
			if not entering then
				manager.focused = false
			end
			manager.schedule({ focus = true })
			return result
		end
	end

	if map.close then
		local original_close = map.close
		map.close = function(...)
			manager.enabled = false
			local args = { ... }
			return manage_windows(function()
				manager.close_all()
				return original_close(unpack(args))
			end)
		end
	end

	local function is_transient_overlay_float(win)
		if not win or not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_config(win).relative == "" then
			return false
		end
		local buf = vim.api.nvim_win_get_buf(win)
		return vim.w[win].dotfiles_glance_preview == true
			or vim.w[win].dotfiles_glance_aerial_layout ~= nil
			or vim.bo[buf].filetype == "Glance"
			or vim.w[win].treesitter_context == true
			or vim.w[win].treesitter_context_line_number == true
	end

	local group = vim.api.nvim_create_augroup("dotfiles-mini-map-code-layout", { clear = true })
	vim.api.nvim_create_autocmd({ "WinNew", "WinClosed", "WinResized", "VimResized" }, {
		group = group,
		callback = function(args)
			if manager.managing_windows > 0 then
				return
			end
			if args.event == "WinNew" then
				inherit_source_margin(vim.api.nvim_get_current_win())
			elseif args.event == "WinClosed" and is_transient_overlay_float(tonumber(args.match)) then
				-- Glance and treesitter-context overlays do not change any source
				-- window's geometry. Re-encoding every minimap as those transient
				-- windows close causes a visible full-editor redraw in diff layouts.
				return
			end
			manager.schedule({ layout = true, integrations = true, lines = true, scrollbar = true })
		end,
	})
	vim.api.nvim_create_autocmd("OptionSet", {
		group = group,
		pattern = "sidescrolloff",
		callback = function()
			if manager.managing_options == 0 and manager.enabled then
				manager.schedule({ layout = true })
			end
		end,
	})
	vim.api.nvim_create_autocmd("OptionSet", {
		group = group,
		pattern = {
			"breakindent",
			"breakindentopt",
			"foldcolumn",
			"linebreak",
			"list",
			"listchars",
			"number",
			"numberwidth",
			"relativenumber",
			"showbreak",
			"signcolumn",
			"statuscolumn",
			"tabstop",
			"vartabstop",
			"wrap",
		},
		callback = function()
			if manager.enabled then
				if vim.wo.linebreak or vim.wo.showbreak ~= "" then
					-- Clear before OptionSet returns: leaving inline padding installed for
					-- the first redraw with either option can crash Neovim 0.12.
					clear_all_wrap_margins()
				else
					manager.schedule({ wrap = true })
				end
			end
		end,
	})
	vim.api.nvim_create_autocmd("WinScrolled", {
		group = group,
		callback = function()
			if manager.managing_windows == 0 and manager.enabled then
				manager.schedule({ wrap = true })
			end
		end,
	})
	vim.api.nvim_create_autocmd("DiagnosticChanged", {
		group = group,
		callback = function()
			if manager.enabled then
				manager.schedule({ wrap = true })
			end
		end,
	})
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "GitSignsUpdate",
		callback = function()
			if manager.enabled then
				manager.schedule({ wrap = true })
			end
		end,
	})
	vim.api.nvim_create_autocmd("WinEnter", {
		group = group,
		callback = function()
			local current = vim.api.nvim_get_current_win()
			if is_code_window(current) then
				local native = map.current.win_data[vim.api.nvim_get_current_tabpage()]
				local window_opts = options().window or {}
				local wanted_width = math.min(window_opts.width or 10, vim.api.nvim_win_get_width(current))
				local geometry_changed = not native
					or not vim.api.nvim_win_is_valid(native)
					or vim.api.nvim_win_get_width(native) ~= wanted_width
					or vim.api.nvim_win_get_height(native) ~= vim.api.nvim_win_get_height(current)
				local source_changed = manager.source_buf ~= vim.api.nvim_win_get_buf(current)

				-- The native map window moves between code windows. Re-encode only
				-- when its grid dimensions or source buffer change; otherwise focus
				-- changes can keep the cheaper scrollbar-only refresh.
				map.refresh({}, {
					integrations = source_changed,
					lines = source_changed or geometry_changed,
					layout = source_changed or geometry_changed,
				})
			else
				manager.schedule({ scrollbar = true })
			end
		end,
	})
	vim.api.nvim_create_autocmd("CursorMoved", {
		group = group,
		callback = function()
			local native = map.current.win_data[vim.api.nvim_get_current_tabpage()]
			if manager.focused and native and vim.api.nvim_get_current_win() == native then
				manager.schedule({ focus = true })
			end
		end,
	})
	manager.schedule({ layout = true, integrations = true, lines = true, scrollbar = true })
end

local function toggle_all_minimaps(map)
	local tabpage = vim.api.nvim_get_current_tabpage()
	local map_win = map.current.win_data[tabpage]
	if map_win and vim.api.nvim_win_is_valid(map_win) then
		map.close()
		vim.cmd.redraw({ bang = true })
		return
	end

	local previous_win = vim.api.nvim_get_current_win()
	local source_win = source_window(map)
	if not source_win then
		return
	end

	if previous_win ~= source_win then
		-- mini.map encodes the current buffer asynchronously. Keep a real code
		-- window current until that first refresh has run, then restore terminal,
		-- explorer, or any other non-code window where the toggle was invoked.
		vim.api.nvim_set_current_win(source_win)
	end
	map.open()

	vim.schedule(function()
		-- Some MiniMap refresh callbacks schedule follow-up work of their own.
		-- Restore one event-loop turn later so all of them still observe source_win.
		vim.schedule(function()
			if previous_win ~= source_win and vim.api.nvim_win_is_valid(previous_win) then
				vim.api.nvim_set_current_win(previous_win)
			end
			vim.cmd.redraw({ bang = true })
		end)
	end)
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
					toggle_all_minimaps(require("mini.map"))
				end,
				desc = "Toggle all minimaps",
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
					winblend = 0,
					-- treesitter-context uses zindex 20. Keep the map above
					-- pinned code while leaving room for menus and popups.
					zindex = 30,
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
			setup_code_layout(map)
			map.open()
			style_minimap_window(map.current.win_data[vim.api.nvim_get_current_tabpage()])
		end,
	},
}
