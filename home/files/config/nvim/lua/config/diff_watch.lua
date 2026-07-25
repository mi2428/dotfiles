local M = {}

local uv = vim.uv or vim.loop
local codex_edits = require("config.codex_edit_watch")
local safe_checktime = require("config.safe_checktime")
local flash_namespace = vim.api.nvim_create_namespace("dotfiles-git-diff-watch-follow")
local default_layout_min_width = 130
local state

local function normalize(path)
	return uv.fs_realpath(path) or vim.fs.normalize(path)
end

local function display_path(path)
	return vim.fn.fnamemodify(path, ":~:.")
end

local function file_metadata(stat)
	local mtime = stat.mtime or {}
	local seconds = mtime.sec or 0
	local nanoseconds = mtime.nsec or 0
	return {
		seconds = seconds,
		nanoseconds = nanoseconds,
		signature = table.concat({ seconds, nanoseconds, stat.size or 0, stat.ino or 0 }, ":"),
	}
end

local function buffer_lines(bufnr)
	return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

local function disk_lines(path)
	local ok, lines = pcall(vim.fn.readfile, path)
	return ok and lines or nil
end

local function last_changed_line(before, after)
	local ok, hunks = pcall(vim.diff, table.concat(before, "\n"), table.concat(after, "\n"), {
		algorithm = "histogram",
		result_type = "indices",
	})
	if not ok or not hunks or #hunks == 0 then
		return nil
	end

	local line = 1
	for _, hunk in ipairs(hunks) do
		local new_start = hunk[3]
		local new_count = hunk[4]
		local hunk_line = new_count > 0 and (new_start + new_count - 1) or new_start
		line = math.max(line, hunk_line)
	end
	return math.min(line, math.max(#after, 1))
end

local function git_baseline_lines(path)
	local relative = vim.fs.relpath(state.repo_root, path)
	if not relative or (state.diff_base == "head" and not state.head_exists) then
		return {}
	end

	local object = state.diff_base == "head" and ("HEAD:%s"):format(relative) or (":%s"):format(relative)
	local result = vim.system({ "git", "-C", state.repo_root, "show", object }, { text = false }):wait()
	if result.code ~= 0 or not result.stdout or result.stdout == "" then
		return {}
	end

	local lines = vim.split(result.stdout, "\n", { plain = true })
	if result.stdout:sub(-1) == "\n" then
		table.remove(lines)
	end
	return lines
end

local function is_empty_buffer(bufnr)
	return vim.api.nvim_buf_is_valid(bufnr)
		and vim.bo[bufnr].buftype == ""
		and vim.api.nvim_buf_get_name(bufnr) == ""
		and not vim.bo[bufnr].modified
		and vim.api.nvim_buf_line_count(bufnr) == 1
		and vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] == ""
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

local function normal_tab_windows()
	local windows = {}
	for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_config(winid).relative == "" then
			windows[#windows + 1] = winid
		end
	end
	return windows
end

local function layout_capacity()
	-- Vertical separators consume one column between adjacent windows.
	local configured = tonumber(vim.g.dotfiles_diff_watch_min_width)
	local minimum = configured and math.max(1, math.floor(configured)) or default_layout_min_width
	return math.max(1, math.floor((vim.o.columns + 1) / (minimum + 1)))
end

local function ensure_file_layout(buffers)
	if #buffers == 0 then
		return
	end

	local watched = {}
	for _, bufnr in ipairs(buffers) do
		watched[bufnr] = true
	end

	local current_win = vim.api.nvim_get_current_win()
	local visible = {}
	local other_windows = 0
	for _, winid in ipairs(normal_tab_windows()) do
		if watched[vim.api.nvim_win_get_buf(winid)] then
			visible[#visible + 1] = winid
		else
			other_windows = other_windows + 1
		end
	end

	local desired = math.min(#buffers, math.max(1, layout_capacity() - other_windows))
	table.sort(visible, function(left, right)
		if left == current_win or right == current_win then
			return left == current_win
		end
		local left_position = vim.api.nvim_win_get_position(left)
		local right_position = vim.api.nvim_win_get_position(right)
		if left_position[1] ~= right_position[1] then
			return left_position[1] < right_position[1]
		end
		return left_position[2] < right_position[2]
	end)

	for index = #visible, desired + 1, -1 do
		local closed = pcall(vim.api.nvim_win_close, visible[index], false)
		if closed then
			table.remove(visible, index)
		end
	end

	local visible_buffers = {}
	for _, winid in ipairs(visible) do
		if vim.api.nvim_win_is_valid(winid) then
			visible_buffers[vim.api.nvim_win_get_buf(winid)] = true
		end
	end

	local primary_win = visible[1]
	if not primary_win or not vim.api.nvim_win_is_valid(primary_win) then
		return
	end

	for _, bufnr in ipairs(buffers) do
		if #visible >= desired then
			break
		end
		if not visible_buffers[bufnr] then
			vim.api.nvim_set_current_win(primary_win)
			vim.cmd("rightbelow vsplit")
			local winid = vim.api.nvim_get_current_win()
			vim.api.nvim_win_set_buf(winid, bufnr)
			visible[#visible + 1] = winid
			visible_buffers[bufnr] = true
		end
	end

	if vim.api.nvim_win_is_valid(primary_win) then
		vim.api.nvim_set_current_win(primary_win)
	end
end

local function parse_paths(output, paths)
	for relative in (output or ""):gmatch("([^%z]+)") do
		local absolute = normalize(vim.fs.joinpath(state.repo_root, relative))
		local stat = uv.fs_stat(absolute)
		if stat and stat.type == "file" then
			paths[absolute] = file_metadata(stat)
		end
	end
end

local function git_error(result)
	local message = vim.trim(result.stderr or result.stdout or "")
	return message ~= "" and message or ("git exited with status %d"):format(result.code or -1)
end

local function run_git(args, callback)
	local command = { "git", "-C", state.scope_dir }
	vim.list_extend(command, args)

	vim.system(command, { text = false }, function(result)
		vim.schedule(function()
			if state and state.active then
				callback(result)
			end
		end)
	end)
end

local function collect_paths(callback)
	local diff_args = { "diff", "--name-only", "--diff-filter=d", "-z" }
	if state.diff_base == "head" and state.head_exists then
		diff_args[#diff_args + 1] = "HEAD"
	elseif state.diff_base == "head" then
		diff_args[#diff_args + 1] = "--cached"
	end
	vim.list_extend(diff_args, { "--", "." })

	run_git(diff_args, function(diff_result)
		if diff_result.code ~= 0 then
			callback(nil, git_error(diff_result))
			return
		end

		run_git(
			{ "ls-files", "--others", "--exclude-standard", "--full-name", "-z", "--", "." },
			function(untracked_result)
				if untracked_result.code ~= 0 then
					callback(nil, git_error(untracked_result))
					return
				end

				local paths = {}
				parse_paths(diff_result.stdout, paths)
				parse_paths(untracked_result.stdout, paths)
				callback(paths)
			end
		)
	end)
end

local function open_new_buffers(paths)
	local current = vim.api.nvim_get_current_buf()
	local replace_empty = is_empty_buffer(current)
	local first_buffer
	local buffers = {}
	local ordered = vim.tbl_keys(paths)
	table.sort(ordered)

	for _, path in ipairs(ordered) do
		local bufnr = find_buffer(path)
		local created = bufnr == nil
		if created then
			bufnr = vim.fn.bufadd(path)
		end

		if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
			vim.bo[bufnr].buflisted = true
			vim.bo[bufnr].autoread = true
			if not vim.api.nvim_buf_is_loaded(bufnr) then
				local loaded = pcall(vim.fn.bufload, bufnr)
				if not loaded then
					bufnr = nil
				end
			end
		end

		if created and bufnr then
			state.owned[bufnr] = path
		end
		if bufnr then
			first_buffer = first_buffer or bufnr
			buffers[#buffers + 1] = bufnr
		end
	end

	if replace_empty and first_buffer and vim.api.nvim_buf_is_valid(first_buffer) then
		vim.api.nvim_set_current_buf(first_buffer)
		if current ~= first_buffer and vim.api.nvim_buf_is_valid(current) then
			pcall(vim.api.nvim_buf_delete, current, {})
		end
	end

	return buffers
end

local function candidate_is_newer(candidate, other)
	if not other then
		return true
	end
	if candidate.seconds ~= other.seconds then
		return candidate.seconds > other.seconds
	end
	if candidate.nanoseconds ~= other.nanoseconds then
		return candidate.nanoseconds > other.nanoseconds
	end
	return candidate.path > other.path
end

local function can_follow_now()
	if not state or not state.follow or vim.api.nvim_get_mode().mode ~= "n" then
		return false
	end

	local current = vim.api.nvim_get_current_buf()
	return not vim.api.nvim_buf_is_valid(current) or not vim.bo[current].modified
end

local function clear_follow_flash()
	if state and state.flash_buffer and vim.api.nvim_buf_is_valid(state.flash_buffer) then
		vim.api.nvim_buf_clear_namespace(state.flash_buffer, flash_namespace, 0, -1)
	end
	if state then
		state.flash_buffer = nil
	end
end

local function flash_follow_line(bufnr, line)
	clear_follow_flash()
	state.flash_generation = state.flash_generation + 1
	state.flash_buffer = bufnr
	local generation = state.flash_generation

	vim.api.nvim_buf_set_extmark(bufnr, flash_namespace, line - 1, 0, {
		line_hl_group = "IncSearch",
		priority = 250,
	})
	vim.defer_fn(function()
		if state and state.flash_generation == generation then
			clear_follow_flash()
		end
	end, 550)
end

local function flush_pending_follow()
	if not state or not state.pending_follow or not can_follow_now() then
		return
	end

	local candidate = state.pending_follow
	if
		(not candidate.codex and not state.paths[candidate.path])
		or not uv.fs_stat(candidate.path)
		or not vim.api.nvim_buf_is_valid(candidate.bufnr)
		or vim.bo[candidate.bufnr].modified
	then
		state.pending_follow = nil
		return
	end

	state.pending_follow = nil
	local winid = vim.fn.bufwinid(candidate.bufnr)
	if winid == -1 or not vim.api.nvim_win_is_valid(winid) then
		winid = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(winid, candidate.bufnr)
	else
		vim.api.nvim_set_current_win(winid)
	end

	local line_count = vim.api.nvim_buf_line_count(candidate.bufnr)
	local line = math.max(1, math.min(candidate.line, line_count))
	vim.api.nvim_win_set_cursor(winid, { line, 0 })
	vim.wo[winid].cursorline = true
	vim.api.nvim_win_call(winid, function()
		vim.cmd("normal! zz")
	end)
	flash_follow_line(candidate.bufnr, line)
	if candidate.on_follow then
		candidate.on_follow()
	end
	vim.api.nvim_echo({ { ("AI → %s:%d"):format(display_path(candidate.path), line), "DiagnosticInfo" } }, false, {})
end

local function queue_follow(candidate)
	if not state.follow or not candidate then
		return
	end
	if candidate_is_newer(candidate, state.pending_follow) then
		state.pending_follow = candidate
	end
	flush_pending_follow()
end

local function refresh_open_buffers(paths)
	local latest
	for path, metadata in pairs(paths) do
		local bufnr = find_buffer(path)
		if bufnr and vim.api.nvim_buf_is_loaded(bufnr) and not vim.bo[bufnr].modified then
			vim.bo[bufnr].autoread = true
			local snapshot = state.snapshots[path]
			if not snapshot or snapshot.signature ~= metadata.signature then
				safe_checktime.checktime(bufnr)

				if not vim.bo[bufnr].modified then
					local lines = buffer_lines(bufnr)
					local saved_lines = disk_lines(path)
					if saved_lines and vim.deep_equal(lines, saved_lines) then
						local line
						if snapshot then
							line = last_changed_line(snapshot.lines, lines)
						elseif state.initialized then
							line = last_changed_line(git_baseline_lines(path), lines)
						end
						state.snapshots[path] = { lines = lines, signature = metadata.signature }

						if line then
							local candidate = {
								bufnr = bufnr,
								line = line,
								nanoseconds = metadata.nanoseconds,
								path = path,
								seconds = metadata.seconds,
							}
							if candidate_is_newer(candidate, latest) then
								latest = candidate
							end
						end
					end
				end
			end
		end
	end
	return latest
end

local function close_clean_buffers(paths)
	for bufnr, path in pairs(state.owned) do
		if not vim.api.nvim_buf_is_valid(bufnr) then
			state.owned[bufnr] = nil
		elseif not paths[path] then
			local current_path = vim.api.nvim_buf_get_name(bufnr)
			if current_path == "" or normalize(current_path) ~= path then
				state.owned[bufnr] = nil
			elseif vim.bo[bufnr].modified then
				state.owned[bufnr] = nil
				vim.notify(
					("Keeping modified buffer after it left the Git diff: %s"):format(display_path(path)),
					vim.log.levels.WARN
				)
			else
				local deleted, err = pcall(vim.api.nvim_buf_delete, bufnr, {})
				state.owned[bufnr] = nil
				if not deleted then
					vim.notify(
						("Failed to close watched buffer %s: %s"):format(display_path(path), err),
						vim.log.levels.WARN
					)
				end
			end
		end
	end
end

local function reconcile(paths)
	local buffers = open_new_buffers(paths)
	local latest = refresh_open_buffers(paths)
	close_clean_buffers(paths)
	ensure_file_layout(buffers)
	for path in pairs(state.snapshots) do
		if not paths[path] then
			state.snapshots[path] = nil
		end
	end
	state.paths = paths
	state.initialized = true
	queue_follow(latest)
	flush_pending_follow()
end

local function remember_written_buffer(bufnr)
	if not state or not state.active or not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	local name = vim.api.nvim_buf_get_name(bufnr)
	local path = name ~= "" and normalize(name) or nil
	if not path or not state.paths[path] then
		return
	end

	local stat = uv.fs_stat(path)
	if not stat or stat.type ~= "file" then
		return
	end

	local metadata = file_metadata(stat)
	state.paths[path] = metadata
	state.snapshots[path] = { lines = buffer_lines(bufnr), signature = metadata.signature }
end

function M.refresh()
	if not state or not state.active or state.in_flight then
		return
	end

	local current = state
	current.in_flight = true
	collect_paths(function(paths, err)
		if state ~= current or not current.active then
			return
		end

		current.in_flight = false
		if not paths then
			if current.last_error ~= err then
				vim.notify(("Git diff watch refresh failed: %s"):format(err), vim.log.levels.ERROR)
				current.last_error = err
			end
			return
		end

		current.last_error = nil
		reconcile(paths)
	end)
end

function M.stop(opts)
	opts = opts or {}
	if not state then
		return
	end

	state.active = false
	codex_edits.stop()
	clear_follow_flash()
	if state.timer and not state.timer:is_closing() then
		state.timer:stop()
		state.timer:close()
	end
	state = nil

	if opts.notify ~= false then
		vim.notify("Git diff watch stopped", vim.log.levels.INFO)
	end
end

function M.toggle_follow()
	if not state then
		vim.notify("Git diff watch is not active", vim.log.levels.WARN)
		return
	end

	state.follow = not state.follow
	if not state.follow then
		state.pending_follow = nil
		clear_follow_flash()
	else
		flush_pending_follow()
	end
	vim.notify(("Git diff watch follow %s"):format(state.follow and "enabled" or "disabled"), vim.log.levels.INFO)
end

function M.start()
	if not state or state.active then
		return
	end

	state.active = true
	state.timer = uv.new_timer()
	if not state.timer then
		state.active = false
		vim.notify("Unable to create Git diff watch timer", vim.log.levels.ERROR)
		return
	end

	vim.o.autoread = true
	state.timer:start(0, state.interval, vim.schedule_wrap(M.refresh))
	vim.notify(
		("Watching %s Git changes%s under %s"):format(
			state.diff_base,
			state.follow and " with follow" or "",
			display_path(state.scope_dir)
		),
		vim.log.levels.INFO
	)
end

function M.is_active()
	return state ~= nil
end

function M.gitsigns_base()
	if state and state.diff_base == "head" and state.head_exists then
		return "HEAD"
	end
end

function M.codex_status()
	return codex_edits.status()
end

function M.setup()
	if vim.env.NVIM_DIFF_WATCH_MODE ~= "1" then
		return
	end

	local repo_root = vim.env.NVIM_DIFF_WATCH_ROOT
	local scope_dir = vim.env.NVIM_DIFF_WATCH_DIR
	local diff_base = vim.env.NVIM_DIFF_WATCH_BASE == "head" and "head" or "worktree"
	local follow = vim.env.NVIM_DIFF_WATCH_FOLLOW == "1"
	local interval = tonumber(vim.env.NVIM_DIFF_WATCH_INTERVAL_MS) or 500
	interval = math.max(100, interval)

	vim.env.NVIM_DIFF_WATCH_MODE = nil
	vim.env.NVIM_DIFF_WATCH_ROOT = nil
	vim.env.NVIM_DIFF_WATCH_DIR = nil
	vim.env.NVIM_DIFF_WATCH_BASE = nil
	vim.env.NVIM_DIFF_WATCH_FOLLOW = nil

	if not repo_root or repo_root == "" or not scope_dir or scope_dir == "" then
		vim.notify("Git diff watch requires a repository root and scope directory", vim.log.levels.ERROR)
		return
	end

	repo_root = normalize(repo_root)
	scope_dir = normalize(scope_dir)
	local head_result = vim.system({ "git", "-C", repo_root, "rev-parse", "--verify", "HEAD" }, { text = true }):wait()

	state = {
		active = false,
		diff_base = diff_base,
		flash_buffer = nil,
		flash_generation = 0,
		follow = follow,
		head_exists = head_result.code == 0,
		in_flight = false,
		initialized = false,
		interval = interval,
		last_error = nil,
		owned = {},
		pending_follow = nil,
		paths = {},
		repo_root = repo_root,
		scope_dir = scope_dir,
		snapshots = {},
		timer = nil,
	}

	codex_edits.setup({
		follow = queue_follow,
		refresh = M.refresh,
		repo_root = repo_root,
		scope_dir = scope_dir,
	})

	vim.api.nvim_create_user_command(
		"VDiffWatchFollowToggle",
		M.toggle_follow,
		{ desc = "Toggle Git diff watch follow" }
	)
	vim.api.nvim_create_user_command("VDiffWatchRefresh", M.refresh, { desc = "Refresh watched Git diff buffers" })
	vim.api.nvim_create_user_command("VDiffWatchStop", M.stop, { desc = "Stop watching Git diff buffers" })

	local group = vim.api.nvim_create_augroup("dotfiles-git-diff-watch", { clear = true })
	vim.api.nvim_create_autocmd("VimEnter", {
		group = group,
		once = true,
		callback = function()
			vim.schedule(M.start)
		end,
	})
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = function()
			M.stop({ notify = false })
		end,
	})
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = group,
		callback = function(args)
			remember_written_buffer(args.buf)
		end,
	})
	vim.api.nvim_create_autocmd({ "BufEnter", "ModeChanged" }, {
		group = group,
		callback = function()
			vim.schedule(flush_pending_follow)
		end,
	})
	vim.api.nvim_create_autocmd("VimResized", {
		group = group,
		callback = function()
			vim.schedule(function()
				if state and state.active then
					ensure_file_layout(open_new_buffers(state.paths))
				end
			end)
		end,
	})
end

return M
