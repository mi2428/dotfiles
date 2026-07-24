local M = {}

local uv = vim.uv or vim.loop
local sign_namespace = vim.api.nvim_create_namespace("dotfiles-codex-edit-signs")
local highlight_namespace = vim.api.nvim_create_namespace("dotfiles-codex-edit-highlights")
local state

local function normalize(path)
	return uv.fs_realpath(path) or vim.fs.normalize(path)
end

local function display_path(path)
	return vim.fn.fnamemodify(path, ":~:.")
end

local function inside_scope(path)
	if not state or not path or path == "" then
		return false
	end
	local relative = vim.fs.relpath(state.scope_dir, path)
	return relative ~= nil and relative ~= ".." and not vim.startswith(relative, "../")
end

local function find_buffer(path)
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(bufnr) then
			local name = vim.api.nvim_buf_get_name(bufnr)
			if name ~= "" and normalize(name) == path then
				return bufnr
			end
		end
	end
end

local function load_buffer(path)
	local stat = uv.fs_stat(path)
	if not stat or stat.type ~= "file" then
		return nil
	end

	local bufnr = find_buffer(path) or vim.fn.bufadd(path)
	if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
		return nil
	end

	vim.bo[bufnr].buflisted = true
	vim.bo[bufnr].autoread = true
	if not vim.api.nvim_buf_is_loaded(bufnr) and not pcall(vim.fn.bufload, bufnr) then
		return nil
	end
	if not vim.bo[bufnr].modified then
		pcall(vim.api.nvim_buf_call, bufnr, function()
			vim.cmd("silent checktime")
		end)
	end
	return bufnr
end

local function event_directory()
	if vim.env.CODEX_NVIM_EDIT_EVENT_DIR and vim.env.CODEX_NVIM_EDIT_EVENT_DIR ~= "" then
		return vim.fs.normalize(vim.fn.expand(vim.env.CODEX_NVIM_EDIT_EVENT_DIR))
	end

	local runtime = vim.env.XDG_RUNTIME_DIR or vim.env.TMPDIR or "/tmp"
	local passwd = uv.os_get_passwd and uv.os_get_passwd() or {}
	local uid = passwd and passwd.uid or 0
	return vim.fs.joinpath(runtime, ("codex-nvim-edit-events-%s"):format(uid))
end

local function redraw()
	vim.cmd("redrawstatus")
	vim.api.nvim_exec_autocmds("User", { pattern = "CodexEditEvent", modeline = false })
end

local function turn_key(event)
	return table.concat({ event.session_id or "", event.turn_id or "" }, ":")
end

local function short_id(value)
	return value and value ~= "" and value:sub(1, 8) or "unknown"
end

local function current_extmark_line(entry)
	if not vim.api.nvim_buf_is_valid(entry.bufnr) then
		return entry.start_line
	end
	local position = vim.api.nvim_buf_get_extmark_by_id(entry.bufnr, sign_namespace, entry.marker_id, {})
	if position and #position >= 1 then
		return position[1] + 1
	end
	return entry.start_line
end

local function jump_to_entry(entry, index)
	if not entry or not uv.fs_stat(entry.path) then
		return false
	end

	local bufnr = load_buffer(entry.path)
	if not bufnr then
		return false
	end
	entry.bufnr = bufnr
	local winid = vim.fn.bufwinid(bufnr)
	if winid == -1 or not vim.api.nvim_win_is_valid(winid) then
		winid = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(winid, bufnr)
	else
		vim.api.nvim_set_current_win(winid)
	end

	local line = math.max(1, math.min(current_extmark_line(entry), vim.api.nvim_buf_line_count(bufnr)))
	vim.api.nvim_win_set_cursor(winid, { line, 0 })
	vim.api.nvim_win_call(winid, function()
		vim.cmd("normal! zz")
	end)
	state.history_index = index
	local message = ("Codex edit %d/%d  %s:%d  turn %s"):format(
		index,
		#state.history,
		display_path(entry.path),
		line,
		short_id(entry.turn_id)
	)
	vim.api.nvim_echo({ { message, "DiagnosticInfo" } }, false, {})
	return true
end

local function navigate_history(direction)
	if not state or #state.history == 0 then
		vim.notify("No Codex edit history", vim.log.levels.INFO)
		return
	end

	local index
	if state.history_index then
		index = state.history_index + direction
	elseif direction < 0 then
		index = #state.history
	else
		index = 1
	end
	if index < 1 then
		index = #state.history
	elseif index > #state.history then
		index = 1
	end

	for _ = 1, #state.history do
		if jump_to_entry(state.history[index], index) then
			return
		end
		index = index + direction
		if index < 1 then
			index = #state.history
		elseif index > #state.history then
			index = 1
		end
	end

	vim.notify("No readable files remain in Codex edit history", vim.log.levels.INFO)
end

local function clear_transient_highlights()
	if not state then
		return
	end
	for bufnr in pairs(state.highlighted_buffers) do
		if vim.api.nvim_buf_is_valid(bufnr) then
			vim.api.nvim_buf_clear_namespace(bufnr, highlight_namespace, 0, -1)
		end
	end
	state.highlighted_buffers = {}
end

local function highlight_entries(entries)
	clear_transient_highlights()
	state.highlight_generation = state.highlight_generation + 1
	local generation = state.highlight_generation

	for _, entry in ipairs(entries) do
		if vim.api.nvim_buf_is_valid(entry.bufnr) then
			local line_count = vim.api.nvim_buf_line_count(entry.bufnr)
			local start_row = math.max(0, math.min(entry.start_line - 1, line_count - 1))
			local end_row = math.max(start_row + 1, math.min(entry.end_line, line_count))
			vim.api.nvim_buf_set_extmark(entry.bufnr, highlight_namespace, start_row, 0, {
				end_row = end_row,
				end_col = 0,
				hl_eol = true,
				hl_group = "Visual",
				priority = 150,
			})
			state.highlighted_buffers[entry.bufnr] = true
		end
	end

	vim.defer_fn(function()
		if state and state.highlight_generation == generation then
			clear_transient_highlights()
		end
	end, 1400)
end

local function trim_history()
	while #state.history > state.history_limit do
		local entry = table.remove(state.history, 1)
		local group = entry and state.turns[entry.turn_key]
		if group then
			for index, candidate in ipairs(group.entries) do
				if candidate == entry then
					table.remove(group.entries, index)
					break
				end
			end
			if #group.entries == 0 then
				state.turns[entry.turn_key] = nil
			end
		end
		if entry and vim.api.nvim_buf_is_valid(entry.bufnr) then
			pcall(vim.api.nvim_buf_del_extmark, entry.bufnr, sign_namespace, entry.marker_id)
		end
		if state.history_index then
			state.history_index = math.max(1, state.history_index - 1)
		end
	end
end

local function add_hunk(event, change, hunk)
	local path = normalize(change.path)
	if not inside_scope(path) then
		return nil
	end
	local bufnr = load_buffer(path)
	if not bufnr then
		return nil
	end

	local line_count = vim.api.nvim_buf_line_count(bufnr)
	local start_line = math.max(1, math.min(tonumber(hunk.start_line) or 1, line_count))
	local end_line = math.max(start_line, math.min(tonumber(hunk.end_line) or start_line, line_count))
	local marker_id = vim.api.nvim_buf_set_extmark(bufnr, sign_namespace, start_line - 1, 0, {
		sign_text = "",
		sign_hl_group = "DiagnosticInfo",
		priority = 30,
	})
	local entry = {
		bufnr = bufnr,
		change_type = hunk.change_type or change.kind or "update",
		emitted_at_ns = tonumber(event.emitted_at_ns) or 0,
		end_line = end_line,
		marker_id = marker_id,
		new_count = tonumber(hunk.new_count) or 0,
		old_count = tonumber(hunk.old_count) or 0,
		path = path,
		session_id = event.session_id,
		span = end_line - start_line + 1,
		start_line = start_line,
		turn_id = event.turn_id,
		turn_key = turn_key(event),
	}
	state.history[#state.history + 1] = entry
	local group = state.turns[entry.turn_key]
	if not group then
		group = { entries = {}, session_id = entry.session_id, turn_id = entry.turn_id }
		state.turns[entry.turn_key] = group
	end
	group.entries[#group.entries + 1] = entry
	return entry
end

local function emit_follow(entry)
	if not state or not entry then
		return
	end
	local seconds = math.floor(entry.emitted_at_ns / 1000000000)
	local nanoseconds = entry.emitted_at_ns % 1000000000
	state.follow({
		bufnr = entry.bufnr,
		codex = true,
		line = entry.start_line,
		nanoseconds = nanoseconds,
		path = entry.path,
		seconds = seconds,
		on_follow = function()
			if state then
				for index, candidate in ipairs(state.history) do
					if candidate == entry then
						state.history_index = index
						break
					end
				end
			end
		end,
	})
end

local function flush_debounced_follow(key)
	if not state or not state.pending_follow or (key and state.pending_follow.turn_key ~= key) then
		return
	end
	local entry = state.pending_follow
	state.pending_follow = nil
	emit_follow(entry)
end

local function debounce_follow(entry)
	state.pending_follow = entry
	state.follow_timer:stop()
	state.follow_timer:start(
		220,
		0,
		vim.schedule_wrap(function()
			flush_debounced_follow()
		end)
	)
end

local function process_patch_event(event)
	local added = {}
	local last_entry
	for _, change in ipairs(event.changes or {}) do
		if type(change) == "table" and type(change.path) == "string" then
			for _, hunk in ipairs(change.hunks or {}) do
				if type(hunk) == "table" then
					local entry = add_hunk(event, change, hunk)
					if entry then
						added[#added + 1] = entry
						last_entry = entry
					end
				end
			end
		end
	end

	state.latest = last_entry or state.latest
	trim_history()
	if #added > 0 then
		state.active_turn = turn_key(event)
		highlight_entries(added)
		debounce_follow(last_entry)
	end
	state.refresh()
	redraw()
end

local function process_event(event)
	if not state or type(event) ~= "table" or event.version ~= 1 then
		return
	end

	if event.type == "patch" then
		process_patch_event(event)
	elseif event.type == "refresh" then
		state.refresh()
	elseif event.type == "stop" then
		local key = turn_key(event)
		flush_debounced_follow(key)
		if state.active_turn == key then
			state.active_turn = nil
		end
		state.refresh()
		redraw()
	end
end

local function decode_event(path)
	local ok, lines = pcall(vim.fn.readfile, path)
	if not ok then
		return nil
	end
	local decoded, event = pcall(vim.json.decode, table.concat(lines, "\n"))
	return decoded and event or nil
end

local function scan_events(process_new)
	if not state then
		return
	end
	local scanner = uv.fs_scandir(state.event_dir)
	if not scanner then
		return
	end

	local names = {}
	while true do
		local name, kind = uv.fs_scandir_next(scanner)
		if not name then
			break
		end
		if kind == "file" and vim.endswith(name, ".event.json") then
			names[#names + 1] = name
		end
	end
	table.sort(names)

	for _, name in ipairs(names) do
		if not state.seen_events[name] then
			state.seen_events[name] = true
			if process_new then
				process_event(decode_event(vim.fs.joinpath(state.event_dir, name)))
			end
		end
	end
end

local function quickfix_items(entries, include_turn)
	local items = {}
	for _, entry in ipairs(entries) do
		if uv.fs_stat(entry.path) then
			local line = current_extmark_line(entry)
			local description = ("Codex %s  -%d +%d"):format(entry.change_type, entry.old_count, entry.new_count)
			if include_turn then
				description = description .. "  turn " .. short_id(entry.turn_id)
			end
			items[#items + 1] = {
				filename = entry.path,
				lnum = line,
				end_lnum = line + entry.span - 1,
				text = description,
				type = "I",
			}
		end
	end
	return items
end

function M.open_quickfix(opts)
	opts = opts or {}
	if not state or not state.latest then
		vim.notify("No Codex edit history", vim.log.levels.INFO)
		return
	end

	local entries
	local title
	if opts.session then
		entries = vim.tbl_filter(function(entry)
			return entry.session_id == state.latest.session_id
		end, state.history)
		title = "Codex edits · session " .. short_id(state.latest.session_id)
	else
		local group = state.turns[state.latest.turn_key]
		entries = group and group.entries or {}
		title = "Codex edits · turn " .. short_id(state.latest.turn_id)
	end

	vim.fn.setqflist({}, " ", {
		title = title,
		items = quickfix_items(entries, opts.session),
	})
	vim.cmd("copen")
end

function M.next_edit()
	navigate_history(1)
end

function M.previous_edit()
	navigate_history(-1)
end

function M.status()
	if not state or not state.latest then
		return nil
	end
	local entry = state.latest
	return {
		active = state.active_turn == entry.turn_key,
		line = current_extmark_line(entry),
		path = display_path(entry.path),
	}
end

function M.stop()
	if not state then
		return
	end
	clear_transient_highlights()
	for _, entry in ipairs(state.history) do
		if vim.api.nvim_buf_is_valid(entry.bufnr) then
			pcall(vim.api.nvim_buf_del_extmark, entry.bufnr, sign_namespace, entry.marker_id)
		end
	end
	if state.fs_event and not state.fs_event:is_closing() then
		state.fs_event:stop()
		state.fs_event:close()
	end
	if state.follow_timer and not state.follow_timer:is_closing() then
		state.follow_timer:stop()
		state.follow_timer:close()
	end
	state = nil
	redraw()
end

function M.setup(opts)
	if state then
		return
	end

	local directory = event_directory()
	vim.fn.mkdir(directory, "p", 448)
	pcall(uv.fs_chmod, directory, 448)
	local fs_event = uv.new_fs_event()
	local follow_timer = uv.new_timer()
	if not fs_event or not follow_timer then
		if fs_event and not fs_event:is_closing() then
			fs_event:close()
		end
		if follow_timer and not follow_timer:is_closing() then
			follow_timer:close()
		end
		vim.notify("Unable to watch Codex edit hook events", vim.log.levels.WARN)
		return
	end

	state = {
		active_turn = nil,
		event_dir = directory,
		follow = opts.follow,
		follow_timer = follow_timer,
		fs_event = fs_event,
		highlight_generation = 0,
		highlighted_buffers = {},
		history = {},
		history_index = nil,
		history_limit = math.max(1, tonumber(opts.history_limit) or 500),
		latest = nil,
		pending_follow = nil,
		refresh = opts.refresh,
		repo_root = normalize(opts.repo_root),
		scope_dir = normalize(opts.scope_dir),
		seen_events = {},
		turns = {},
	}

	-- Existing events predate this editor instance and must not replay.
	scan_events(false)
	fs_event:start(
		directory,
		{},
		vim.schedule_wrap(function()
			scan_events(true)
		end)
	)
	vim.schedule(function()
		scan_events(true)
	end)

	vim.keymap.set("n", "]a", function()
		M.next_edit()
	end, { desc = "Next Codex edit" })
	vim.keymap.set("n", "[a", function()
		M.previous_edit()
	end, { desc = "Previous Codex edit" })
	vim.api.nvim_create_user_command("VDiffWatchCodexQuickfix", function(command)
		M.open_quickfix({ session = command.bang })
	end, { bang = true, desc = "Open Codex edit quickfix (! for current session)" })
end

M._test = {
	event_directory = event_directory,
	history_size = function()
		return state and #state.history or 0
	end,
	process_event = process_event,
}

return M
