local M = {}

local search_backend = "noice.view.backend.dotfiles_search_count"

local search_groups = {
	arrow = "TinyInlineDiagnosticVirtualTextArrowNoBg",
	body = "TinyInlineDiagnosticVirtualTextInfo",
	cap = "TinyInlineInvDiagnosticVirtualTextInfoNoBg",
}

M.search_count_debounce_ms = 150
M.search_count_timeout_ms = 20

local fallback_signs = {
	arrow = "    ",
	left = "",
	right = "",
}

local fallback_search_icons = {
	down = " ",
	up = " ",
}

local function tiny_inline_style()
	local ok, tiny_inline = pcall(require, "tiny-inline-diagnostic")
	local config = ok and tiny_inline.config or nil
	local signs = config and config.signs or fallback_signs

	return {
		arrow = signs.arrow or fallback_signs.arrow,
		left = signs.left or fallback_signs.left,
		right = signs.right or fallback_signs.right,
	}
end

local function search_icon(message)
	local direction = vim.trim(message):sub(1, 1) == "?" and "up" or "down"
	local ok, Config = pcall(require, "noice.config")
	local format = ok and Config.options.cmdline and Config.options.cmdline.format
	local configured = format and format["search_" .. direction]
	return (configured and configured.icon) or fallback_search_icons[direction]
end

local function search_count_label(message)
	local current, total = message:match("%[([^/%]]+)/([^%]]+)%]%s*$")
	if current and total then
		return ("Match %s of %s"):format(current, total)
	end
	return vim.trim(message)
end

function M.evaluate_search_count()
	local ok, count = pcall(vim.fn.searchcount, {
		recompute = true,
		maxcount = vim.o.maxsearchcount,
		timeout = M.search_count_timeout_ms,
	})
	if not ok or type(count) ~= "table" then
		return
	end

	local exact = count.exact_match == 1 or count.exact_match == true
	if not exact or count.current == 0 or count.total == 0 or count.incomplete == 1 then
		return
	end

	return count
end

function M.search_count_message(direction, count)
	local total = count.incomplete == 2 and (">" .. vim.o.maxsearchcount) or tostring(count.total)
	return ("%s [%s/%s]"):format(direction, count.current, total)
end

function M.search_count_virtual_text(message)
	local style = tiny_inline_style()

	return {
		{ style.arrow, search_groups.arrow },
		{ style.left, search_groups.cap },
		{ " ", search_groups.body },
		{ search_icon(message), search_groups.body },
		{ " " .. search_count_label(message) .. " ", search_groups.body },
		{ style.right, search_groups.cap },
	}
end

local function has_tiny_inline_diagnostic(buf, line)
	local namespace = vim.api.nvim_get_namespaces().TinyInlineDiagnostic
	if not namespace then
		return false
	end

	return #vim.api.nvim_buf_get_extmarks(buf, namespace, { line, 0 }, { line, -1 }, {
		details = false,
		overlap = true,
	}) > 0
end

local function tiny_inline_diagnostic_chip_col(buf, line)
	local namespace = vim.api.nvim_get_namespaces().TinyInlineDiagnostic
	if not namespace then
		return
	end

	local style = tiny_inline_style()
	local marks = vim.api.nvim_buf_get_extmarks(buf, namespace, { line, 0 }, { line, -1 }, {
		details = true,
		overlap = true,
	})
	for _, mark in ipairs(marks) do
		local details = mark[4]
		local column = details.virt_text_win_col
		if column and details.virt_text then
			for _, chunk in ipairs(details.virt_text) do
				if chunk[1] == style.left then
					return column
				end
				column = column + vim.fn.strdisplaywidth(chunk[1])
			end
		end
	end
end

function M.search_count_extmark_options(buf, line, message)
	local chunks = M.search_count_virtual_text(message)
	local options = {
		hl_mode = "combine",
		priority = 4096,
	}

	if not has_tiny_inline_diagnostic(buf, line) then
		options.virt_text = chunks
		options.virt_text_pos = "eol"
		return options
	end

	-- EOL virtual text and tiny-inline-diagnostic both start at the physical
	-- end of the line and priorities do not reserve horizontal space. Give the
	-- transient search status its own row whenever a diagnostic owns that EOL.
	local line_text = vim.api.nvim_buf_get_lines(buf, line, line + 1, false)[1] or ""
	local style = tiny_inline_style()
	local padding = tiny_inline_diagnostic_chip_col(buf, line)
		or (vim.fn.strdisplaywidth(line_text) + 1 + vim.fn.strdisplaywidth(style.arrow))
	-- The diagnostic already draws the shared relation arrow. Start this row at
	-- the diagnostic's left cap so both pill bodies form one aligned stack.
	chunks = vim.list_slice(chunks, 2)
	local virtual_line = { { (" "):rep(padding), "None" } }
	vim.list_extend(virtual_line, chunks)

	options.virt_lines = { virtual_line }
	options.virt_lines_above = true
	return options
end

local function register_search_count_backend()
	package.preload[search_backend] = function()
		local Config = require("noice.config")
		local View = require("noice.view")
		local SearchCount = View:extend("DotfilesNoiceSearchCountView")

		function SearchCount:_clear_extmark()
			if self.extmark and self.buf and vim.api.nvim_buf_is_valid(self.buf) then
				pcall(vim.api.nvim_buf_del_extmark, self.buf, Config.ns, self.extmark)
			end
			self.extmark = nil
			self.buf = nil
			self.rendered_cursor = nil
		end

		function SearchCount:_in_source_context()
			return self.active
				and self.source_win
				and vim.api.nvim_win_is_valid(self.source_win)
				and vim.api.nvim_get_current_win() == self.source_win
				and vim.api.nvim_win_get_buf(self.source_win) == self.source_buf
				and vim.api.nvim_buf_is_valid(self.source_buf)
				and vim.api.nvim_buf_is_loaded(self.source_buf)
		end

		function SearchCount:_source_state_is_current()
			return self:_in_source_context()
				and vim.api.nvim_buf_get_changedtick(self.source_buf) == self.source_changedtick
				and vim.v.hlsearch == 1
				and vim.fn.getreg("/") == self.source_pattern
		end

		function SearchCount:_display(message)
			self:_clear_extmark()
			if not self:_in_source_context() then
				return
			end

			local line = vim.api.nvim_win_get_cursor(self.source_win)[1]
			local zero_line = line - 1
			local text = vim.api.nvim_buf_get_lines(self.source_buf, zero_line, line, false)[1] or ""
			self.buf = self.source_buf
			self.extmark = vim.api.nvim_buf_set_extmark(
				self.source_buf,
				Config.ns,
				zero_line,
				#text,
				M.search_count_extmark_options(self.source_buf, zero_line, message)
			)
			self.rendered_cursor = vim.api.nvim_win_get_cursor(self.source_win)
		end

		function SearchCount:_refresh()
			if not self:_source_state_is_current() then
				self:_clear_extmark()
				return
			end

			local count = M.evaluate_search_count()
			if not count then
				self:_clear_extmark()
				return
			end

			self.last_message = M.search_count_message(self.direction, count)
			self:_display(self.last_message)
		end

		function SearchCount:_schedule_refresh(delay)
			if not self.active or not self.timer then
				return
			end

			self.timer:stop()
			local generation = self.generation
			self.timer:start(delay or M.search_count_debounce_ms, 0, function()
				vim.schedule(function()
					if self.active and self.generation == generation then
						self:_refresh()
					end
				end)
			end)
		end

		function SearchCount:_refresh_layout()
			local generation = self.generation
			local cursor = self.rendered_cursor and vim.deepcopy(self.rendered_cursor)
			vim.schedule(function()
				if
					self.active
					and self.generation == generation
					and self.last_message
					and cursor
					and self:_source_state_is_current()
					and vim.deep_equal(vim.api.nvim_win_get_cursor(self.source_win), cursor)
				then
					self:_display(self.last_message)
				end
			end)
		end

		function SearchCount:_start_tracking()
			self.timer = assert(vim.uv.new_timer())
			self.augroup = vim.api.nvim_create_augroup("dotfiles-noice-search-count-" .. self._id, { clear = true })

			vim.api.nvim_create_autocmd({ "CursorMoved", "TextChanged" }, {
				group = self.augroup,
				callback = function()
					if self.active then
						self:_clear_extmark()
						self:_schedule_refresh()
					end
				end,
			})
			vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave", "InsertEnter" }, {
				group = self.augroup,
				callback = function()
					if self.active then
						self:_clear_extmark()
					end
				end,
			})
			vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter", "InsertLeave" }, {
				group = self.augroup,
				callback = function()
					self:_schedule_refresh()
				end,
			})
			vim.api.nvim_create_autocmd("DiagnosticChanged", {
				group = self.augroup,
				callback = function(args)
					if args.buf == self.source_buf then
						self:_refresh_layout()
					end
				end,
			})
			vim.api.nvim_create_autocmd("CmdlineLeave", {
				group = self.augroup,
				callback = function()
					self:_schedule_refresh(0)
				end,
			})
			vim.api.nvim_create_autocmd("WinClosed", {
				group = self.augroup,
				callback = function(args)
					if tonumber(args.match) == self.source_win then
						self:hide()
					end
				end,
			})
		end

		function SearchCount:show()
			self:hide()
			if not self._messages[1] then
				return
			end

			self.active = true
			self.generation = (self.generation or 0) + 1
			self.source_win = vim.api.nvim_get_current_win()
			self.source_buf = vim.api.nvim_get_current_buf()
			self.source_changedtick = vim.api.nvim_buf_get_changedtick(self.source_buf)
			self.source_pattern = vim.fn.getreg("/")
			self.last_message = self._messages[1]:content()
			self.direction = vim.trim(self.last_message):sub(1, 1) == "?" and "?" or "/"
			self:_start_tracking()
			self:_display(self.last_message)
		end

		function SearchCount:hide()
			self.active = false
			self.generation = (self.generation or 0) + 1
			if self.timer then
				self.timer:stop()
				if not self.timer:is_closing() then
					self.timer:close()
				end
				self.timer = nil
			end
			if self.augroup then
				pcall(vim.api.nvim_del_augroup_by_id, self.augroup)
				self.augroup = nil
			end
			self:_clear_extmark()
			self.source_win = nil
			self.source_buf = nil
			self.source_changedtick = nil
			self.source_pattern = nil
			self.last_message = nil
		end

		return SearchCount
	end
end

function M.setup()
	register_search_count_backend()
end

return M
