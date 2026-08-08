local M = {}
local default_max_markdown_bytes = 1024 * 1024
local large_markdown_bytes = 512 * 1024
local ghostty_browser_pane
local ghostty_browser_generation = 0
local herdr_browser_pane
local herdr_browser_executable
local herdr_browser_generation = 0
local generic_browser_job
local generic_browser_record
local generic_browser_generation = 0

-- Ghostty can deliver `initial input` before its macOS login shell is ready and discard the command.
-- Launch terminal-browser as the split's process instead, so no shell input timing is involved.
local ghostty_split_script = [[
on run argv
  set marker to item 1 of argv
  set cmdText to item 2 of argv
  set workingDirectory to item 3 of argv
  tell application "Ghostty"
    repeat with w in windows
      repeat with tb in tabs of w
        repeat with term in terminals of tb
          if (name of term) contains marker then
            set childTerm to split term direction right with configuration {command:cmdText, initial working directory:workingDirectory, wait after command:false}
            return id of childTerm
          end if
        end repeat
      end repeat
    end repeat
    error "could not find the marked Neovim pane"
  end tell
end run
]]

local ghostty_close_script = [[
on run argv
  set targetId to item 1 of argv
  tell application "Ghostty"
    repeat with w in windows
      repeat with tb in tabs of w
        repeat with term in terminals of tb
          if (id of term) as text is targetId then
            close term
            return "ok"
          end if
        end repeat
      end repeat
    end repeat
  end tell
  return "not-found"
end run
]]

local state = {
	active = false,
	bufnr = nil,
	job_id = nil,
	ready = false,
	url = nil,
	generation = 0,
	seq = 0,
	timer = nil,
	oversize_notified = false,
	render_markdown_enabled = nil,
	setup_done = false,
}

local function close_herdr_browser()
	herdr_browser_generation = herdr_browser_generation + 1
	local pane = herdr_browser_pane
	local executable = herdr_browser_executable
	herdr_browser_pane = nil
	herdr_browser_executable = nil
	if pane and pane ~= "" and executable and executable ~= "" then
		vim.system({ executable, "pane", "close", pane }, { text = true }, function(result)
			if result.code ~= 0 then
				vim.schedule(function()
					vim.notify(
						"Failed to close the Markdown preview pane in Herdr: " .. vim.trim(result.stderr),
						vim.log.levels.ERROR
					)
				end)
			end
		end)
	end
end

local function notify(message, level)
	vim.schedule(function()
		vim.notify(message, level)
	end)
end

local function notify_error(message)
	notify(message, vim.log.levels.ERROR)
end

local function stop_after_browser_error(message)
	notify_error(message)
	vim.schedule(function()
		M.stop()
	end)
end

local function close_generic_browser_record(record)
	if type(record) ~= "table" then
		return
	end

	if type(record.openedTab) == "number" and type(record.socket) == "string" and record.socket ~= "" then
		local pipe = vim.uv.new_pipe(false)
		pipe:connect(record.socket, function(connect_error)
			if connect_error then
				pipe:close()
				return
			end
			pipe:write(vim.json.encode({ cmd = "close-tab", tab = record.openedTab }) .. "\n", function()
				pipe:shutdown(function()
					pipe:close()
				end)
			end)
		end)
		return
	end

	local tty = type(record.tty) == "string" and record.tty:match("^/dev/(.+)$") or nil
	if tty and tty ~= "" then
		-- A fresh generic split has one terminal-browser client on its own TTY. Terminating
		-- that client asks the daemon to close the session without killing shared browsers.
		vim.system({ "pkill", "-TERM", "-t", tty, "-f", "terminal-browser" }, { text = true }, function() end)
	end
end

local function close_generic_browser()
	generic_browser_generation = generic_browser_generation + 1
	local job = generic_browser_job
	local record = generic_browser_record
	generic_browser_job = nil
	generic_browser_record = nil
	close_generic_browser_record(record)

	-- Let an in-flight `open` return its ownership record so its callback can close the
	-- split. Only force-stop a command that outlives terminal-browser's own 20s timeout.
	if job then
		vim.defer_fn(function()
			pcall(vim.fn.jobstop, job)
		end, 21000)
	end
end

local function current_buffer(bufnr)
	bufnr = bufnr or 0
	return bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
end

local function shell_command(argv)
	return table.concat(
		vim.tbl_map(function(arg)
			return vim.fn.shellescape(arg)
		end, argv),
		" "
	)
end

local function open_in_herdr(url)
	local parent = vim.env.HERDR_PANE_ID
	local executable = vim.fn.exepath("herdr")
	if vim.env.HERDR_ENV ~= "1" or not parent or parent == "" or executable == "" then
		return false
	end
	if herdr_browser_pane then
		close_herdr_browser()
	end
	herdr_browser_generation = herdr_browser_generation + 1
	local generation = herdr_browser_generation

	-- Ghostty title probing cannot identify a busy Herdr TUI pane, so split by its stable pane ID.
	vim.system({
		executable,
		"pane",
		"split",
		"--pane",
		parent,
		"--direction",
		"right",
		"--ratio",
		"0.5",
		"--cwd",
		vim.fn.getcwd(),
		"--no-focus",
	}, { text = true }, function(result)
		if result.code ~= 0 then
			if generation == herdr_browser_generation then
				stop_after_browser_error("Failed to create a browser pane: " .. vim.trim(result.stderr))
			end
			return
		end

		local ok, payload = pcall(vim.json.decode, result.stdout)
		local pane = ok and payload.result and payload.result.pane and payload.result.pane.pane_id or nil
		if not pane then
			if generation == herdr_browser_generation then
				stop_after_browser_error("Failed to read the browser pane ID from Herdr")
			end
			return
		end
		if generation == herdr_browser_generation then
			herdr_browser_pane = pane
			herdr_browser_executable = executable
		else
			vim.system({ executable, "pane", "close", pane }, { text = true }, function() end)
			return
		end

		vim.schedule(function()
			if generation ~= herdr_browser_generation then
				vim.system({ executable, "pane", "close", pane }, { text = true }, function() end)
				return
			end
			vim.system(
				{ executable, "pane", "run", pane, "terminal-browser", "open", url },
				{ text = true },
				function(run)
					if generation ~= herdr_browser_generation then
						vim.system({ executable, "pane", "close", pane }, { text = true }, function() end)
						return
					end
					if run.code ~= 0 then
						close_herdr_browser()
						stop_after_browser_error("Failed to start terminal-browser in Herdr: " .. vim.trim(run.stderr))
					end
				end
			)
		end)
	end)
	return true
end

local function current_tty()
	local pid = vim.fn.getpid()
	for _ = 1, 30 do
		local result = vim.system({ "ps", "-o", "ppid=,tty=", "-p", tostring(pid) }, { text = true }):wait()
		if result.code ~= 0 then
			return nil
		end

		local parent, tty = vim.trim(result.stdout):match("^(%d+)%s+(%S+)$")
		if not parent or not tty then
			return nil
		end
		if tty ~= "??" then
			return vim.startswith(tty, "/") and tty or "/dev/" .. tty
		end

		pid = tonumber(parent)
		if not pid or pid <= 1 then
			return nil
		end
	end
	return nil
end

local function set_pane_title(tty, title)
	local fd = vim.uv.fs_open(tty, "w", 0)
	if not fd then
		return false
	end

	local written = vim.uv.fs_write(fd, ("\27]2;%s\7"):format(title), -1)
	vim.uv.fs_close(fd)
	return written ~= nil
end

local function close_ghostty_pane(pane)
	if not pane or pane == "" then
		return
	end
	vim.system({ "osascript", "-", pane }, { text = true, stdin = ghostty_close_script }, function(result)
		if result.code ~= 0 then
			notify_error("Failed to close the Markdown preview pane in Ghostty: " .. vim.trim(result.stderr))
		end
	end)
end

local function close_ghostty_browser()
	ghostty_browser_generation = ghostty_browser_generation + 1
	local pane = ghostty_browser_pane
	ghostty_browser_pane = nil
	close_ghostty_pane(pane)
end

local function buffer_root(bufnr)
	local name = vim.api.nvim_buf_get_name(bufnr)
	if name == "" then
		local cwd = vim.fs.normalize(vim.fn.getcwd())
		return cwd, vim.fs.joinpath(cwd, "untitled.md")
	end

	name = vim.fs.normalize(name)
	local dir = vim.fs.normalize(vim.fs.dirname(name))
	local git_dir = vim.fs.find(".git", { path = dir, upward = true, limit = 1 })[1]
	local root = vim.fs.normalize(git_dir and vim.fs.dirname(git_dir) or dir)
	return root, name
end

local function open_in_ghostty(url)
	if
		vim.env.TERM_PROGRAM ~= "ghostty"
		or (vim.env.TMUX and vim.env.TMUX ~= "")
		or vim.env.HERDR_ENV == "1"
		or vim.env.CMUX_BUNDLE_ID
		or vim.fn.executable("osascript") ~= 1
	then
		return false
	end

	local tty = current_tty()
	if not tty then
		notify_error("Failed to identify the Ghostty pane TTY")
		return true
	end

	local browser = vim.fn.exepath("terminal-browser")
	local command = shell_command({
		browser,
		"open",
		url,
		"--split-dir=right",
		"--parent-tty=" .. tty,
	})
	local marker = ("markdown-preview-%d-%d"):format(vim.fn.getpid(), math.random(100000000, 999999999))
	local attempts = 0
	ghostty_browser_generation = ghostty_browser_generation + 1
	local generation = ghostty_browser_generation
	if ghostty_browser_pane then
		close_ghostty_pane(ghostty_browser_pane)
		ghostty_browser_pane = nil
	end

	local function split()
		attempts = attempts + 1
		if not set_pane_title(tty, marker) then
			if generation == ghostty_browser_generation then
				stop_after_browser_error("Failed to mark the Ghostty pane at " .. tty)
			end
			return
		end

		vim.defer_fn(function()
			vim.system(
				{ "osascript", "-", marker, command, vim.fn.getcwd() },
				{ text = true, stdin = ghostty_split_script },
				function(result)
					if result.code == 0 then
						local pane = vim.trim(result.stdout)
						if pane == "" then
							if generation == ghostty_browser_generation then
								stop_after_browser_error("Ghostty did not return the Markdown preview pane ID")
							end
						elseif generation == ghostty_browser_generation then
							ghostty_browser_pane = pane
						else
							close_ghostty_pane(pane)
						end
						return
					end
					vim.schedule(function()
						if generation ~= ghostty_browser_generation then
							return
						end
						if attempts < 6 then
							split()
							return
						end
						local message = vim.trim(result.stderr)
						stop_after_browser_error(
							"Failed to start terminal-browser in Ghostty: "
								.. (message ~= "" and message or ("exit code %d"):format(result.code))
						)
					end)
				end
			)
		end, 150)
	end

	split()
	return true
end

function M.is_markdown_buffer(bufnr)
	bufnr = current_buffer(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end

	local filetype = vim.bo[bufnr].filetype
	return filetype == "markdown"
		or (filetype == "bigfile" and vim.b[bufnr].dotfiles_bigfile_original_filetype == "markdown")
end

function M.open_browser(url)
	if vim.fn.executable("terminal-browser") ~= 1 then
		vim.notify("terminal-browser is not available", vim.log.levels.ERROR)
		return
	end
	if type(url) ~= "string" or url == "" then
		vim.notify("Markdown preview returned an invalid URL", vim.log.levels.ERROR)
		return
	end
	if open_in_herdr(url) then
		return
	end
	if open_in_ghostty(url) then
		return
	end

	local errors = {}
	local output = {}
	local preview_generation = state.generation
	close_generic_browser()
	generic_browser_generation = generic_browser_generation + 1
	local browser_generation = generic_browser_generation
	local job = vim.fn.jobstart({ "terminal-browser", "open", url, "--split", "right", "--size", "0.5" }, {
		detach = false,
		stdout_buffered = true,
		stderr_buffered = true,
		on_stdout = function(_, data)
			for _, line in ipairs(data or {}) do
				if line ~= "" then
					output[#output + 1] = line
				end
			end
		end,
		on_stderr = function(_, data)
			for _, line in ipairs(data or {}) do
				if line ~= "" then
					errors[#errors + 1] = line
				end
			end
		end,
		on_exit = function(_, code)
			vim.schedule(function()
				local record
				if #output > 0 then
					local ok, decoded = pcall(vim.json.decode, table.concat(output, "\n"))
					record = ok and decoded or nil
				end
				local current = browser_generation == generic_browser_generation
					and preview_generation == state.generation
					and state.active
				if current then
					generic_browser_job = nil
					generic_browser_record = record
				else
					close_generic_browser_record(record)
				end
				if code ~= 0 and current then
					local message = #errors > 0 and table.concat(errors, "\n") or ("exit code %d"):format(code)
					stop_after_browser_error("terminal-browser failed: " .. message)
				end
			end)
		end,
	})
	if job <= 0 then
		stop_after_browser_error(("Failed to start terminal-browser (code %d)"):format(job))
	else
		generic_browser_job = job
	end
end

local function set_toggle_state(bufnr, value)
	if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
		vim.b[bufnr].MarkdownPreviewToggleBool = value and 1 or 0
	end
end

local function maybe_call(module, method)
	if type(module) ~= "table" or type(module[method]) ~= "function" then
		return
	end
	if pcall(module[method]) then
		return
	end
	pcall(module[method], module)
end

local function set_render_markdown_enabled(enabled)
	local ok, render_markdown = pcall(require, "render-markdown")
	if not ok then
		return
	end
	maybe_call(render_markdown, enabled and "enable" or "disable")
end

local function render_markdown_enabled()
	local ok, render_markdown = pcall(require, "render-markdown")
	if not ok or type(render_markdown.get) ~= "function" then
		return nil
	end
	local status_ok, enabled = pcall(render_markdown.get)
	if status_ok and type(enabled) == "boolean" then
		return enabled
	end
	return nil
end

local function paths()
	local overrides = vim.g.dotfiles_markdown_preview_paths or {}
	local config_dir = overrides.config_dir or vim.fn.stdpath("config")
	local root = vim.fs.joinpath(config_dir, "markdown-preview")
	return {
		config_dir = config_dir,
		node = overrides.node or vim.fn.exepath("node"),
		comrak = overrides.comrak or vim.fn.exepath("comrak"),
		server = overrides.server or vim.fs.joinpath(root, "server.mjs"),
		mermaid = overrides.mermaid
			or vim.env.MARKDOWN_PREVIEW_MERMAID_JS
			or vim.fs.joinpath(root, "vendor", "mermaid.min.js"),
	}
end

local function ensure_backend()
	local p = paths()
	if p.node == "" then
		notify_error("node is not available for Markdown preview")
		return nil
	end
	if p.comrak == "" then
		notify_error("comrak is not available for Markdown preview")
		return nil
	end
	if vim.fn.executable("terminal-browser") ~= 1 then
		notify_error("terminal-browser is not available for Markdown preview")
		return nil
	end
	if vim.fn.filereadable(p.server) ~= 1 then
		notify_error("Markdown preview server is missing: " .. p.server)
		return nil
	end
	if vim.fn.filereadable(p.mermaid) ~= 1 then
		notify_error("Markdown preview Mermaid bundle is missing: " .. p.mermaid)
		return nil
	end
	return p
end

local function ensure_timer()
	if state.timer and not state.timer:is_closing() then
		return state.timer
	end
	state.timer = vim.uv.new_timer()
	return state.timer
end

local function stop_timer()
	if not state.timer then
		return
	end
	state.timer:stop()
	if not state.timer:is_closing() then
		state.timer:close()
	end
	state.timer = nil
end

local function cursor_line(bufnr)
	if current_buffer() == bufnr then
		return vim.api.nvim_win_get_cursor(0)[1]
	end
	return 1
end

local function buffer_markdown(bufnr)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	return table.concat(lines, "\n")
end

local function max_markdown_bytes()
	local configured = tonumber(vim.g.dotfiles_markdown_preview_max_bytes)
	return math.max(1, math.floor(configured or default_max_markdown_bytes))
end

local function buffer_byte_size(bufnr)
	local line_count = vim.api.nvim_buf_line_count(bufnr)
	local ok, bytes = pcall(vim.api.nvim_buf_get_offset, bufnr, line_count)
	-- The end-of-buffer offset includes a synthetic final newline that table.concat does not send.
	return ok and math.max(0, bytes - 1) or #buffer_markdown(bufnr)
end

local function render_debounce_ms(bufnr)
	local configured = tonumber(vim.g.dotfiles_markdown_preview_debounce_ms)
	if configured then
		return math.max(0, math.floor(configured))
	end
	return buffer_byte_size(bufnr) >= large_markdown_bytes and 750 or 150
end

local function buffer_size_allowed(bufnr, notify_once)
	local bytes = buffer_byte_size(bufnr)
	local limit = max_markdown_bytes()
	if bytes <= limit then
		state.oversize_notified = false
		return true
	end
	if not notify_once or not state.oversize_notified then
		notify(("Markdown preview skipped %d-byte buffer (limit: %d bytes)"):format(bytes, limit), vim.log.levels.WARN)
	end
	state.oversize_notified = true
	return false
end

local function payload_base(bufnr)
	local root, source_path = buffer_root(bufnr)
	return {
		cursorLine = cursor_line(bufnr),
		sourcePath = source_path,
		root = root,
	}
end

local function send(payload)
	if not state.active or state.job_id == nil then
		return false
	end
	state.seq = state.seq + 1
	payload.seq = state.seq
	return vim.fn.chansend(state.job_id, vim.json.encode(payload) .. "\n") > 0
end

local function send_render(bufnr)
	if not state.ready or not state.active or state.bufnr ~= bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end
	if not buffer_size_allowed(bufnr, true) then
		return
	end
	local payload = payload_base(bufnr)
	payload.type = "render"
	payload.markdown = buffer_markdown(bufnr)
	send(payload)
end

local function send_cursor(bufnr)
	if not state.ready or not state.active or state.bufnr ~= bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end
	send({
		type = "cursor",
		line = cursor_line(bufnr),
	})
end

local function schedule_render(bufnr)
	if not state.active or state.bufnr ~= bufnr then
		return
	end
	local generation = state.generation
	local timer = ensure_timer()
	timer:stop()
	timer:start(render_debounce_ms(bufnr), 0, function()
		vim.schedule(function()
			if generation ~= state.generation then
				return
			end
			send_render(bufnr)
		end)
	end)
end

local function reset_state(enable_render_markdown, stop_job)
	local previous_render_markdown = state.render_markdown_enabled
	stop_timer()
	close_generic_browser()
	close_ghostty_browser()
	close_herdr_browser()
	if stop_job and state.job_id ~= nil then
		pcall(vim.fn.chanclose, state.job_id, "stdin")
		pcall(vim.fn.jobstop, state.job_id)
	end
	set_toggle_state(state.bufnr, false)
	state.active = false
	state.bufnr = nil
	state.job_id = nil
	state.ready = false
	state.url = nil
	state.seq = 0
	state.oversize_notified = false
	state.render_markdown_enabled = nil
	if enable_render_markdown and previous_render_markdown ~= nil then
		set_render_markdown_enabled(previous_render_markdown)
	end
end

local function handle_stdout(data, generation, output)
	if generation ~= state.generation or not state.active then
		return
	end
	for _, line in ipairs(data or {}) do
		if line == "" then
			goto continue
		end
		local ok, payload = pcall(vim.json.decode, output.stdout_tail .. line)
		if not ok then
			output.stdout_tail = output.stdout_tail .. line
			goto continue
		end
		output.stdout_tail = ""
		if payload.type == "ready" and type(payload.url) == "string" and payload.url ~= "" then
			state.ready = true
			state.url = payload.url
			M.open_browser(payload.url)
			send_render(state.bufnr)
		end
		::continue::
	end
end

function M.start(bufnr)
	M.setup()
	bufnr = current_buffer(bufnr)
	if not M.is_markdown_buffer(bufnr) then
		notify("Markdown preview is only available in Markdown buffers", vim.log.levels.WARN)
		return false
	end
	if not buffer_size_allowed(bufnr, false) then
		return false
	end

	if state.active and state.bufnr == bufnr and state.job_id ~= nil then
		set_toggle_state(bufnr, true)
		schedule_render(bufnr)
		return true
	end

	local p = ensure_backend()
	if not p then
		return false
	end

	if state.active then
		M.stop()
	end

	state.generation = state.generation + 1
	state.active = true
	state.bufnr = bufnr
	state.ready = false
	state.url = nil
	state.seq = 0
	state.oversize_notified = false
	state.render_markdown_enabled = render_markdown_enabled()
	set_toggle_state(bufnr, true)
	if state.render_markdown_enabled ~= nil then
		set_render_markdown_enabled(false)
	end

	local generation = state.generation
	local output = { stdout_tail = "", stderr = {} }
	local job_id = vim.fn.jobstart({ p.node, p.server }, {
		cwd = p.config_dir,
		env = {
			COMRAK_BIN = p.comrak,
			MERMAID_JS = p.mermaid,
			MARKDOWN_PREVIEW_MAX_BYTES = tostring(max_markdown_bytes()),
		},
		stdout_buffered = false,
		stderr_buffered = false,
		on_stdout = function(_, data)
			handle_stdout(data, generation, output)
		end,
		on_stderr = function(_, data)
			if generation ~= state.generation then
				return
			end
			for _, line in ipairs(data or {}) do
				if line ~= "" then
					output.stderr[#output.stderr + 1] = line
				end
			end
		end,
		on_exit = function(_, code)
			vim.schedule(function()
				if generation ~= state.generation then
					return
				end
				local message = #output.stderr > 0 and table.concat(output.stderr, "\n")
					or ("exit code %d"):format(code)
				reset_state(true, false)
				if code ~= 0 then
					notify_error("Markdown preview server failed: " .. message)
				end
			end)
		end,
	})
	if job_id <= 0 then
		reset_state(true, true)
		notify_error(("Failed to start Markdown preview server (code %d)"):format(job_id))
		return false
	end

	state.job_id = job_id
	local startup_timeout = tonumber(vim.g.dotfiles_markdown_preview_startup_timeout) or 5000
	vim.defer_fn(function()
		if generation ~= state.generation or not state.active or state.ready then
			return
		end
		notify_error(("Markdown preview server did not become ready within %d ms"):format(startup_timeout))
		M.stop()
	end, startup_timeout)
	return true
end

function M.stop()
	if not state.active then
		return
	end
	local job_id = state.job_id
	state.generation = state.generation + 1
	if job_id ~= nil then
		pcall(send, { type = "shutdown" })
		pcall(vim.fn.chanclose, job_id, "stdin")
		vim.defer_fn(function()
			pcall(vim.fn.jobstop, job_id)
		end, 200)
	end
	reset_state(true, false)
end

function M.toggle()
	if state.active then
		M.stop()
		return
	end
	M.start()
end

local function active_markdown_buf(bufnr)
	return state.active and state.bufnr == bufnr and M.is_markdown_buffer(bufnr)
end

function M.setup()
	if state.setup_done then
		return
	end
	state.setup_done = true

	local group = vim.api.nvim_create_augroup("dotfiles-markdown-preview", { clear = true })
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		group = group,
		callback = function(args)
			if active_markdown_buf(args.buf) then
				schedule_render(args.buf)
			end
		end,
	})
	vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
		group = group,
		callback = function(args)
			if active_markdown_buf(args.buf) then
				send_cursor(args.buf)
			end
		end,
	})
	vim.api.nvim_create_autocmd("BufEnter", {
		group = group,
		callback = function(args)
			if not state.active then
				return
			end
			if M.is_markdown_buffer(args.buf) then
				set_toggle_state(state.bufnr, false)
				state.bufnr = args.buf
				set_toggle_state(args.buf, true)
				schedule_render(args.buf)
			end
		end,
	})
	vim.api.nvim_create_autocmd("BufWipeout", {
		group = group,
		callback = function(args)
			if state.active and state.bufnr == args.buf then
				M.stop()
			end
		end,
	})
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = function()
			M.stop()
		end,
	})

	vim.api.nvim_create_user_command("MarkdownPreview", function()
		M.start()
	end, {})
	vim.api.nvim_create_user_command("MarkdownPreviewStop", function()
		M.stop()
	end, {})
	vim.api.nvim_create_user_command("MarkdownPreviewToggle", function()
		M.toggle()
	end, {})
end

return M
