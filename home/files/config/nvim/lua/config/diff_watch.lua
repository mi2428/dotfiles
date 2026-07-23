local M = {}

local uv = vim.uv or vim.loop
local state

local function normalize(path)
	return vim.fs.normalize(path)
end

local function display_path(path)
	return vim.fn.fnamemodify(path, ":~:.")
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

local function parse_paths(output, paths)
	for relative in (output or ""):gmatch("([^%z]+)") do
		local absolute = normalize(vim.fs.joinpath(state.repo_root, relative))
		local stat = uv.fs_stat(absolute)
		if stat and stat.type == "file" then
			paths[absolute] = true
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
	local first_new
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
			first_new = first_new or bufnr
		end
	end

	if replace_empty and first_new and vim.api.nvim_buf_is_valid(first_new) then
		vim.api.nvim_set_current_buf(first_new)
		if current ~= first_new and vim.api.nvim_buf_is_valid(current) then
			pcall(vim.api.nvim_buf_delete, current, {})
		end
	end
end

local function refresh_open_buffers(paths)
	for path in pairs(paths) do
		local bufnr = find_buffer(path)
		if bufnr and vim.api.nvim_buf_is_loaded(bufnr) and not vim.bo[bufnr].modified then
			vim.bo[bufnr].autoread = true
			pcall(vim.api.nvim_buf_call, bufnr, function()
				vim.cmd("silent checktime")
			end)
		end
	end
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
	open_new_buffers(paths)
	refresh_open_buffers(paths)
	close_clean_buffers(paths)
	state.paths = paths
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
	if state.timer and not state.timer:is_closing() then
		state.timer:stop()
		state.timer:close()
	end
	state = nil

	if opts.notify ~= false then
		vim.notify("Git diff watch stopped", vim.log.levels.INFO)
	end
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
		("Watching %s Git changes under %s"):format(state.diff_base, display_path(state.scope_dir)),
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

function M.setup()
	if vim.env.NVIM_DIFF_WATCH_MODE ~= "1" then
		return
	end

	local repo_root = vim.env.NVIM_DIFF_WATCH_ROOT
	local scope_dir = vim.env.NVIM_DIFF_WATCH_DIR
	local diff_base = vim.env.NVIM_DIFF_WATCH_BASE == "head" and "head" or "worktree"
	local interval = tonumber(vim.env.NVIM_DIFF_WATCH_INTERVAL_MS) or 500
	interval = math.max(100, interval)

	vim.env.NVIM_DIFF_WATCH_MODE = nil
	vim.env.NVIM_DIFF_WATCH_ROOT = nil
	vim.env.NVIM_DIFF_WATCH_DIR = nil
	vim.env.NVIM_DIFF_WATCH_BASE = nil

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
		head_exists = head_result.code == 0,
		in_flight = false,
		interval = interval,
		last_error = nil,
		owned = {},
		paths = {},
		repo_root = repo_root,
		scope_dir = scope_dir,
		timer = nil,
	}

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
end

return M
