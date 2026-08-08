local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
vim.opt.runtimepath:prepend(nvim_root)
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")

local preview = require("config.markdown_preview")
preview.setup()

local function shell_command(argv)
	return table.concat(
		vim.tbl_map(function(arg)
			return vim.fn.shellescape(arg)
		end, argv),
		" "
	)
end

local function write_executable(path, lines)
	vim.fn.writefile(lines, path)
	vim.fn.setfperm(path, "rwx------")
end

local function read_json_lines(path)
	if vim.fn.filereadable(path) ~= 1 then
		return {}
	end
	local items = {}
	for _, line in ipairs(vim.fn.readfile(path)) do
		if line ~= "" then
			items[#items + 1] = vim.json.decode(line)
		end
	end
	return items
end

local function wait_for(predicate, message, timeout)
	assert(vim.wait(timeout or 4000, predicate, 20), message)
end

local function canonical(path)
	return vim.uv.fs_realpath(path) or vim.fs.normalize(path)
end

local function with_env(temp_dir, fn)
	local old_path = vim.env.PATH
	local old_term_program = vim.env.TERM_PROGRAM
	local old_tmux = vim.env.TMUX
	local old_herdr_env = vim.env.HERDR_ENV
	local old_herdr_pane_id = vim.env.HERDR_PANE_ID
	local old_cmux_bundle_id = vim.env.CMUX_BUNDLE_ID
	local old_paths = vim.g.dotfiles_markdown_preview_paths
	local old_startup_timeout = vim.g.dotfiles_markdown_preview_startup_timeout
	local old_max_bytes = vim.g.dotfiles_markdown_preview_max_bytes
	local old_debounce_ms = vim.g.dotfiles_markdown_preview_debounce_ms
	local old_render_markdown = package.loaded["render-markdown"]
	local ok, err = xpcall(fn, debug.traceback)
	preview.stop()
	package.loaded["render-markdown"] = old_render_markdown
	vim.g.dotfiles_markdown_preview_paths = old_paths
	vim.g.dotfiles_markdown_preview_startup_timeout = old_startup_timeout
	vim.g.dotfiles_markdown_preview_max_bytes = old_max_bytes
	vim.g.dotfiles_markdown_preview_debounce_ms = old_debounce_ms
	vim.env.PATH = old_path
	vim.env.TERM_PROGRAM = old_term_program
	vim.env.TMUX = old_tmux
	vim.env.HERDR_ENV = old_herdr_env
	vim.env.HERDR_PANE_ID = old_herdr_pane_id
	vim.env.CMUX_BUNDLE_ID = old_cmux_bundle_id
	vim.fn.delete(temp_dir, "rf")
	assert(ok, err)
end

local function make_fake_backend(temp_dir, url)
	local events_file = vim.fs.joinpath(temp_dir, "events.ndjson")
	local args_file = vim.fs.joinpath(temp_dir, "node-args")
	local starts_file = vim.fs.joinpath(temp_dir, "starts")
	local max_bytes_file = vim.fs.joinpath(temp_dir, "max-bytes")
	local browser_args_file = vim.fs.joinpath(temp_dir, "browser-args")
	local node = vim.fs.joinpath(temp_dir, "node")
	local comrak = vim.fs.joinpath(temp_dir, "comrak")
	local browser = vim.fs.joinpath(temp_dir, "terminal-browser")
	local config_dir = vim.fs.joinpath(temp_dir, "config")
	local preview_dir = vim.fs.joinpath(config_dir, "markdown-preview")
	local server = vim.fs.joinpath(preview_dir, "server.mjs")
	local mermaid = vim.fs.joinpath(preview_dir, "vendor", "mermaid.min.js")

	vim.fn.mkdir(vim.fs.dirname(mermaid), "p")
	vim.fn.writefile({ "// fake server" }, server)
	vim.fn.writefile({ "// fake mermaid" }, mermaid)
	write_executable(comrak, { "#!/bin/sh", "exit 0" })
	write_executable(browser, {
		"#!/bin/sh",
		"printf '%s\\n' \"$@\" > " .. vim.fn.shellescape(browser_args_file),
	})
	write_executable(node, {
		"#!/bin/sh",
		"printf '%s\\n' \"$@\" > " .. vim.fn.shellescape(args_file),
		"printf '%s\\n' \"$MARKDOWN_PREVIEW_MAX_BYTES\" > " .. vim.fn.shellescape(max_bytes_file),
		"printf x >> " .. vim.fn.shellescape(starts_file),
		"printf '%s\\n' " .. vim.fn.shellescape(vim.json.encode({ type = "ready", url = url })),
		"while IFS= read -r line; do",
		"  printf '%s\\n' \"$line\" >> " .. vim.fn.shellescape(events_file),
		'  case "$line" in',
		'    *\'"type":"shutdown"\'*) exit 0 ;;',
		"  esac",
		"done",
	})

	return {
		temp_dir = temp_dir,
		events_file = events_file,
		args_file = args_file,
		starts_file = starts_file,
		max_bytes_file = max_bytes_file,
		browser_args_file = browser_args_file,
		config_dir = config_dir,
		server = server,
		mermaid = mermaid,
		node = node,
		comrak = comrak,
		browser = browser,
	}
end

local function set_fake_paths(fake)
	vim.g.dotfiles_markdown_preview_paths = {
		config_dir = fake.config_dir,
		node = fake.node,
		comrak = fake.comrak,
		server = fake.server,
		mermaid = fake.mermaid,
	}
	vim.env.PATH = fake.temp_dir .. ":" .. vim.env.PATH
	vim.env.TERM_PROGRAM = "xterm-ghostless"
	vim.env.TMUX = "/tmp/test-tmux"
	vim.env.HERDR_ENV = nil
	vim.env.HERDR_PANE_ID = nil
	vim.env.CMUX_BUNDLE_ID = nil
end

local markdown_buf = vim.api.nvim_create_buf(false, true)
vim.bo[markdown_buf].filetype = "markdown"
vim.api.nvim_buf_set_lines(markdown_buf, 0, -1, false, { "# Title", "body" })
assert(preview.is_markdown_buffer(markdown_buf), "markdown buffers must be supported")

local big_markdown_buf = vim.api.nvim_create_buf(false, true)
vim.bo[big_markdown_buf].filetype = "bigfile"
vim.b[big_markdown_buf].dotfiles_bigfile_original_filetype = "markdown"
assert(preview.is_markdown_buffer(big_markdown_buf), "bigfile Markdown buffers must be supported")

local generic_bigfile_buf = vim.api.nvim_create_buf(false, true)
vim.bo[generic_bigfile_buf].filetype = "bigfile"
vim.b[generic_bigfile_buf].dotfiles_bigfile_original_filetype = "lua"
assert(not preview.is_markdown_buffer(generic_bigfile_buf), "generic bigfile buffers must not be supported")

do
	local temp_dir = vim.fn.tempname()
	local fake = make_fake_backend(temp_dir, "http://127.0.0.1:8123/page/1")
	with_env(temp_dir, function()
		set_fake_paths(fake)
		local disabled = 0
		local enabled = 0
		local repo_dir_path = vim.fs.joinpath(temp_dir, "repo")
		local named_path_raw = vim.fs.joinpath(repo_dir_path, "docs", "note.md")
		vim.fn.mkdir(vim.fs.joinpath(repo_dir_path, ".git"), "p")
		vim.fn.mkdir(vim.fs.dirname(named_path_raw), "p")
		vim.fn.writefile({}, named_path_raw)
		local repo_dir = canonical(repo_dir_path)
		local named_path = canonical(named_path_raw)
		vim.api.nvim_buf_set_name(markdown_buf, named_path)
		package.loaded["render-markdown"] = {
			get = function()
				return true
			end,
			disable = function()
				disabled = disabled + 1
			end,
			enable = function()
				enabled = enabled + 1
			end,
		}

		vim.api.nvim_set_current_buf(markdown_buf)
		vim.api.nvim_win_set_cursor(0, { 2, 0 })
		assert(preview.start(), "preview must start for Markdown buffers")
		assert(preview.start(), "restarting the same active buffer must be idempotent")

		wait_for(function()
			return vim.fn.filereadable(fake.browser_args_file) == 1 and #read_json_lines(fake.events_file) >= 1
		end, "timed out waiting for preview startup")

		assert(
			vim.deep_equal(vim.fn.readfile(fake.args_file), { fake.server }),
			"node must start the configured server"
		)
		assert(vim.fn.getfsize(fake.starts_file) == 1, "idempotent start must not spawn a second server")
		assert(
			vim.deep_equal(vim.fn.readfile(fake.max_bytes_file), { "1048576" }),
			"Neovim and the backend must share the default Markdown byte limit"
		)
		assert(
			vim.deep_equal(vim.fn.readfile(fake.browser_args_file), {
				"open",
				"http://127.0.0.1:8123/page/1",
				"--split",
				"right",
				"--size",
				"0.5",
			}),
			"terminal-browser arguments must preserve the preview layout contract"
		)

		local events = read_json_lines(fake.events_file)
		assert(events[1].type == "render", "startup must render the current buffer")
		assert(events[1].markdown == "# Title\nbody", "startup render must use the full unsaved buffer")
		assert(events[1].cursorLine == 2, "startup render must include the current cursor line")
		assert(
			events[1].root == repo_dir,
			"named buffer root must resolve to the enclosing git root: " .. vim.inspect(events[1])
		)
		assert(events[1].sourcePath == named_path, "named buffer sourcePath must use the real buffer path")

		vim.api.nvim_buf_set_lines(markdown_buf, 1, 2, false, { "old" })
		vim.api.nvim_exec_autocmds("TextChanged", { buffer = markdown_buf })
		vim.api.nvim_buf_set_lines(markdown_buf, 1, 2, false, { "newest" })
		vim.api.nvim_exec_autocmds("TextChangedI", { buffer = markdown_buf })
		wait_for(function()
			local items = read_json_lines(fake.events_file)
			return #items >= 2 and items[#items].type == "render"
		end, "timed out waiting for debounced render")

		events = read_json_lines(fake.events_file)
		assert(#events == 2, "text changes must debounce to one latest render")
		assert(events[2].markdown == "# Title\nnewest", "debounced render must send the latest buffer contents")

		vim.api.nvim_win_set_cursor(0, { 1, 0 })
		vim.api.nvim_exec_autocmds("CursorMoved", { buffer = markdown_buf })
		wait_for(function()
			local items = read_json_lines(fake.events_file)
			return #items >= 3 and items[#items].type == "cursor"
		end, "timed out waiting for cursor sync")

		events = read_json_lines(fake.events_file)
		assert(events[3].line == 1, "cursor updates must send cursor-only payloads")
		assert(events[3].cursorLine == nil, "cursor updates must not resend render metadata")
		assert(disabled == 0, "preview must not change the editor's render-markdown style")

		local unnamed_buf = vim.api.nvim_create_buf(false, true)
		vim.bo[unnamed_buf].filetype = "markdown"
		vim.api.nvim_buf_set_lines(unnamed_buf, 0, -1, false, { "scratch" })
		vim.api.nvim_set_current_buf(unnamed_buf)
		vim.api.nvim_exec_autocmds("BufEnter", { buffer = unnamed_buf })
		wait_for(function()
			local items = read_json_lines(fake.events_file)
			return #items >= 4 and items[#items].type == "render"
		end, "timed out waiting for unnamed buffer render")
		events = read_json_lines(fake.events_file)
		local cwd = vim.fs.normalize(vim.fn.getcwd())
		assert(events[4].root == cwd, "unnamed buffer root must fall back to cwd")
		assert(
			events[4].sourcePath == vim.fs.joinpath(cwd, "untitled.md"),
			"unnamed buffer sourcePath must use root/untitled.md"
		)

		preview.stop()
		wait_for(function()
			local items = read_json_lines(fake.events_file)
			return #items >= 5 and items[#items].type == "shutdown"
		end, "timed out waiting for preview shutdown")
		assert(enabled == 0, "preview stop must not change the editor's render-markdown style")
		assert(vim.b[markdown_buf].MarkdownPreviewToggleBool == 0, "stop must clear the active toggle flag")
		vim.api.nvim_set_current_buf(markdown_buf)
		vim.api.nvim_buf_delete(unnamed_buf, { force = true })
	end)
end

do
	local temp_dir = vim.fn.tempname()
	local fake = make_fake_backend(temp_dir, "http://127.0.0.1:8123/page/render-state")
	with_env(temp_dir, function()
		set_fake_paths(fake)
		local disabled = 0
		local enabled = 0
		package.loaded["render-markdown"] = {
			get = function()
				return false
			end,
			disable = function()
				disabled = disabled + 1
			end,
			enable = function()
				enabled = enabled + 1
			end,
		}
		vim.api.nvim_set_current_buf(markdown_buf)
		assert(preview.start(markdown_buf), "preview must start when render-markdown is already disabled")
		wait_for(function()
			return vim.fn.filereadable(fake.starts_file) == 1
		end, "timed out waiting for render-state preview")
		preview.stop()
		assert(disabled == 0, "preview must leave an already-disabled render-markdown state alone")
		assert(enabled == 0, "preview must not enable render-markdown when it started disabled")
	end)
end

do
	local temp_dir = vim.fn.tempname()
	local fake = make_fake_backend(temp_dir, "http://127.0.0.1:8123/page/oversize")
	with_env(temp_dir, function()
		set_fake_paths(fake)
		vim.g.dotfiles_markdown_preview_max_bytes = 8
		vim.api.nvim_set_current_buf(markdown_buf)
		vim.api.nvim_buf_set_lines(markdown_buf, 0, -1, false, { "01234567" })
		assert(preview.start(markdown_buf), "an exact-limit Markdown buffer must be accepted")
		wait_for(function()
			local items = read_json_lines(fake.events_file)
			return #items >= 1 and items[1].markdown == "01234567"
		end, "timed out waiting for exact-limit render")
		assert(
			vim.deep_equal(vim.fn.readfile(fake.max_bytes_file), { "8" }),
			"custom byte limits must reach the backend"
		)
		preview.stop()
		vim.api.nvim_buf_set_lines(markdown_buf, 0, -1, false, { "0123456789" })
		assert(not preview.start(markdown_buf), "oversized Markdown buffers must be rejected before backend startup")
		vim.wait(100)
		assert(vim.fn.getfsize(fake.starts_file) == 1, "oversized buffers must not launch a second backend")
		vim.api.nvim_buf_set_lines(markdown_buf, 0, -1, false, { "# Title", "body" })
	end)
end

do
	local temp_dir = vim.fn.tempname()
	local fake = make_fake_backend(temp_dir, "http://127.0.0.1:8123/page/large-debounce")
	with_env(temp_dir, function()
		set_fake_paths(fake)
		vim.api.nvim_set_current_buf(markdown_buf)
		vim.api.nvim_buf_set_lines(markdown_buf, 0, -1, false, { string.rep("x", 600 * 1024) })
		assert(preview.start(markdown_buf), "large in-limit Markdown must start")
		wait_for(function()
			return vim.fn.filereadable(fake.events_file) == 1 and #vim.fn.readfile(fake.events_file) == 1
		end, "timed out waiting for initial large render")
		vim.api.nvim_buf_set_text(markdown_buf, 0, 0, 0, 1, { "y" })
		vim.api.nvim_exec_autocmds("TextChangedI", { buffer = markdown_buf })
		vim.wait(300)
		assert(#vim.fn.readfile(fake.events_file) == 1, "large edits must use the extended debounce")
		wait_for(function()
			return #vim.fn.readfile(fake.events_file) == 2
		end, "timed out waiting for debounced large render", 2000)
		preview.stop()
		vim.api.nvim_buf_set_lines(markdown_buf, 0, -1, false, { "# Title", "body" })
	end)
end

do
	local temp_dir = vim.fn.tempname()
	local fake = make_fake_backend(temp_dir, "http://127.0.0.1:8123/page/new")
	write_executable(fake.browser, { "#!/bin/sh", "exit 0" })
	write_executable(fake.node, {
		"#!/bin/sh",
		"printf x >> " .. vim.fn.shellescape(fake.starts_file),
		"count=$(wc -c < " .. vim.fn.shellescape(fake.starts_file) .. ")",
		'if [ "$count" -eq 1 ]; then',
		"  while IFS= read -r line; do :; done",
		"  sleep 0.05",
		"  printf '%s' '{\"type\":\"stale'",
		"  sleep 0.3",
		"  exit 0",
		"fi",
		"sleep 0.15",
		"printf '%s\\n' "
			.. vim.fn.shellescape(vim.json.encode({ type = "ready", url = "http://127.0.0.1:8123/page/new" })),
		"while IFS= read -r line; do",
		"  printf '%s\\n' \"$line\" >> " .. vim.fn.shellescape(fake.events_file),
		'  case "$line" in',
		'    *\'"type":"shutdown"\'*) exit 0 ;;',
		"  esac",
		"done",
	})
	with_env(temp_dir, function()
		set_fake_paths(fake)
		vim.api.nvim_set_current_buf(markdown_buf)
		assert(preview.start(markdown_buf), "first partial-output preview must start")
		wait_for(function()
			return vim.fn.getfsize(fake.starts_file) == 1
		end, "timed out waiting for first partial-output backend")
		preview.stop()
		assert(preview.start(markdown_buf), "preview must restart after partial output")
		wait_for(function()
			return #read_json_lines(fake.events_file) >= 1
		end, "stale stdout must not poison the restarted ready message")
		assert(vim.b[markdown_buf].MarkdownPreviewToggleBool == 1, "restarted preview must remain active")
		preview.stop()
	end)
end

do
	local temp_dir = vim.fn.tempname()
	local fake = make_fake_backend(temp_dir, "http://127.0.0.1:8123/page/generic-owned")
	local pkill_args_file = vim.fs.joinpath(temp_dir, "pkill-args")
	write_executable(fake.browser, {
		"#!/bin/sh",
		"printf '%s\\n' \"$@\" > " .. vim.fn.shellescape(fake.browser_args_file),
		"printf '%s\\n' " .. vim.fn.shellescape(
			vim.json.encode({ key = "fake-1", tty = "/dev/ttys999", socket = "/tmp/missing.sock" })
		),
	})
	write_executable(vim.fs.joinpath(temp_dir, "pkill"), {
		"#!/bin/sh",
		"printf '%s\\n' \"$@\" > " .. vim.fn.shellescape(pkill_args_file),
	})
	with_env(temp_dir, function()
		set_fake_paths(fake)
		vim.api.nvim_set_current_buf(markdown_buf)
		assert(preview.start(markdown_buf), "generic browser ownership preview must start")
		wait_for(function()
			return vim.fn.filereadable(fake.browser_args_file) == 1
		end, "timed out waiting for generic browser launch")
		vim.wait(100)
		preview.stop()
		wait_for(function()
			return vim.fn.filereadable(pkill_args_file) == 1
		end, "stopping preview must close its fresh generic browser")
		assert(
			vim.deep_equal(vim.fn.readfile(pkill_args_file), { "-TERM", "-t", "ttys999", "-f", "terminal-browser" }),
			"generic browser cleanup must target only the owned split TTY"
		)
	end)
end

do
	local temp_dir = vim.fn.tempname()
	local fake = make_fake_backend(temp_dir, "http://127.0.0.1:8123/page/browser-failure")
	write_executable(fake.browser, { "#!/bin/sh", "printf 'browser failed' >&2", "exit 9" })
	with_env(temp_dir, function()
		set_fake_paths(fake)
		vim.api.nvim_set_current_buf(markdown_buf)
		assert(preview.start(markdown_buf), "preview backend must start before the browser failure")
		wait_for(function()
			return vim.b[markdown_buf].MarkdownPreviewToggleBool == 0
		end, "browser launch failure must stop the preview backend")
		wait_for(function()
			local items = read_json_lines(fake.events_file)
			return #items >= 1 and items[#items].type == "shutdown"
		end, "browser launch failure must send backend shutdown")
	end)
end

do
	local temp_dir = vim.fn.tempname()
	local fake = make_fake_backend(temp_dir, "http://127.0.0.1:8123/page/race")
	write_executable(fake.browser, { "#!/bin/sh", "exit 0" })
	write_executable(fake.node, {
		"#!/bin/sh",
		"printf x >> " .. vim.fn.shellescape(fake.starts_file),
		"count=$(wc -c < " .. vim.fn.shellescape(fake.starts_file) .. ")",
		'if [ "$count" -eq 1 ]; then',
		"  printf '%s\\n' "
			.. vim.fn.shellescape(vim.json.encode({ type = "ready", url = "http://127.0.0.1:8123/page/old" })),
		"  while IFS= read -r line; do",
		"    printf '%s\\n' \"$line\" >> " .. vim.fn.shellescape(fake.events_file),
		"  done",
		"  sleep 0.4",
		"  exit 0",
		"fi",
		"printf '%s\\n' "
			.. vim.fn.shellescape(vim.json.encode({ type = "ready", url = "http://127.0.0.1:8123/page/new" })),
		"while IFS= read -r line; do",
		"  printf '%s\\n' \"$line\" >> " .. vim.fn.shellescape(fake.events_file),
		'  case "$line" in',
		'    *\'"type":"shutdown"\'*) exit 0 ;;',
		"  esac",
		"done",
	})
	with_env(temp_dir, function()
		set_fake_paths(fake)
		local named_path = vim.fs.joinpath(temp_dir, "race.md")
		vim.fn.writefile({}, named_path)
		vim.api.nvim_buf_set_name(markdown_buf, named_path)
		vim.api.nvim_set_current_buf(markdown_buf)
		assert(preview.start(markdown_buf), "first preview must start")
		wait_for(function()
			return #read_json_lines(fake.events_file) >= 1
		end, "timed out waiting for first preview render")
		preview.stop()
		assert(preview.start(markdown_buf), "second preview must start before first job exits")
		wait_for(function()
			return vim.fn.getfsize(fake.starts_file) == 2 and #read_json_lines(fake.events_file) >= 3
		end, "timed out waiting for restarted preview render")
		vim.wait(800)
		assert(
			vim.b[markdown_buf].MarkdownPreviewToggleBool == 1,
			"stale old-job exit must not clear the new preview state"
		)
		local before = #read_json_lines(fake.events_file)
		vim.api.nvim_win_set_cursor(0, { 1, 0 })
		vim.api.nvim_exec_autocmds("CursorMoved", { buffer = markdown_buf })
		wait_for(function()
			return #read_json_lines(fake.events_file) > before
		end, "timed out waiting for cursor event after stale old-job exit")
		local events = read_json_lines(fake.events_file)
		assert(events[#events].type == "cursor", "new preview must remain active after stale old-job exit")
		preview.stop()
	end)
end

do
	local temp_dir = vim.fn.tempname()
	local fake = make_fake_backend(temp_dir, "http://127.0.0.1:8123/never-ready")
	write_executable(fake.node, {
		"#!/bin/sh",
		"while IFS= read -r line; do",
		"  printf '%s\\n' \"$line\" >> " .. vim.fn.shellescape(fake.events_file),
		"done",
	})
	with_env(temp_dir, function()
		set_fake_paths(fake)
		vim.g.dotfiles_markdown_preview_startup_timeout = 50
		vim.api.nvim_set_current_buf(markdown_buf)
		assert(preview.start(markdown_buf), "preview with a stalled backend must start its readiness timer")
		wait_for(function()
			return vim.b[markdown_buf].MarkdownPreviewToggleBool == 0
		end, "stalled backend must stop after the readiness timeout")
	end)
end

do
	local temp_dir = vim.fn.tempname()
	local fake = make_fake_backend(temp_dir, "http://127.0.0.1:8123/page/2")
	with_env(temp_dir, function()
		set_fake_paths(fake)
		local lua_buf = vim.api.nvim_create_buf(false, true)
		vim.bo[lua_buf].filetype = "lua"
		vim.api.nvim_set_current_buf(lua_buf)
		assert(not preview.start(lua_buf), "non-Markdown buffers must be rejected")
		vim.api.nvim_set_current_buf(markdown_buf)
		vim.api.nvim_buf_delete(lua_buf, { force = true })
		assert(vim.fn.filereadable(fake.args_file) == 0, "non-Markdown buffers must not launch the backend")
	end)
end

do
	local temp_dir = vim.fn.tempname()
	local fake = make_fake_backend(temp_dir, "http://127.0.0.1:8123/page/4")
	local herdr_calls_file = vim.fs.joinpath(temp_dir, "herdr-calls")
	local fake_herdr = vim.fs.joinpath(temp_dir, "herdr")
	write_executable(fake.node, {
		"#!/bin/sh",
		"printf '%s\\n' \"$@\" > " .. vim.fn.shellescape(fake.args_file),
		"printf x >> " .. vim.fn.shellescape(fake.starts_file),
		"while IFS= read -r line; do",
		"  printf '%s\\n' \"$line\" >> " .. vim.fn.shellescape(fake.events_file),
		'  case "$line" in',
		'    *\'"type":"shutdown"\'*) exit 0 ;;',
		"  esac",
		"done",
	})
	write_executable(fake_herdr, {
		"#!/bin/sh",
		"printf '%s\\n' \"$@\" >> " .. vim.fn.shellescape(herdr_calls_file),
		"if [ \"$2\" = 'split' ]; then",
		'  printf \'%s\\n\' \'{"result":{"pane":{"pane_id":"pane-77"}}}\'',
		"elif [ \"$2\" = 'run' ]; then",
		"  exit 0",
		"elif [ \"$2\" = 'close' ]; then",
		"  exit 0",
		"fi",
	})

	with_env(temp_dir, function()
		set_fake_paths(fake)
		vim.env.HERDR_ENV = "1"
		vim.env.HERDR_PANE_ID = "parent-22"
		local named_path = vim.fs.joinpath(temp_dir, "herdr.md")
		vim.fn.writefile({}, named_path)
		vim.api.nvim_buf_set_name(markdown_buf, named_path)
		vim.api.nvim_set_current_buf(markdown_buf)
		assert(vim.fn.executable("herdr") == 1, "Herdr test must use the fake herdr executable from PATH")
		assert(preview.start(markdown_buf), "Herdr preview must start")
		preview.open_browser("http://127.0.0.1:8123/page/4")
		wait_for(function()
			local calls = vim.fn.filereadable(herdr_calls_file) == 1 and vim.fn.readfile(herdr_calls_file) or {}
			return vim.deep_equal(calls, {
				"pane",
				"split",
				"--pane",
				"parent-22",
				"--direction",
				"right",
				"--ratio",
				"0.5",
				"--cwd",
				vim.fn.getcwd(),
				"--no-focus",
				"pane",
				"run",
				"pane-77",
				"terminal-browser",
				"open",
				"http://127.0.0.1:8123/page/4",
			})
		end, "timed out waiting for Herdr split/run")
		vim.wait(100)
		preview.stop()
		wait_for(function()
			local calls = vim.fn.readfile(herdr_calls_file)
			for index = 1, #calls - 2 do
				if calls[index] == "pane" and calls[index + 1] == "close" and calls[index + 2] == "pane-77" then
					return true
				end
			end
			return false
		end, "timed out waiting for Herdr close")
		local calls = vim.fn.readfile(herdr_calls_file)
		assert(
			vim.deep_equal(vim.list_slice(calls, 1, 17), {
				"pane",
				"split",
				"--pane",
				"parent-22",
				"--direction",
				"right",
				"--ratio",
				"0.5",
				"--cwd",
				vim.fn.getcwd(),
				"--no-focus",
				"pane",
				"run",
				"pane-77",
				"terminal-browser",
				"open",
				"http://127.0.0.1:8123/page/4",
			}),
			"Herdr preview must split and run terminal-browser before stop: " .. vim.inspect(calls)
		)
		assert(vim.tbl_contains(calls, "close"), "Herdr preview must close the pane on stop: " .. vim.inspect(calls))
	end)
end

do
	local temp_dir = vim.fn.tempname()
	local fake = make_fake_backend(temp_dir, "http://127.0.0.1:8123/page/4b")
	local herdr_calls_file = vim.fs.joinpath(temp_dir, "herdr-run-fail-calls")
	local fake_herdr = vim.fs.joinpath(temp_dir, "herdr")
	write_executable(fake.node, {
		"#!/bin/sh",
		"printf '%s\\n' \"$@\" > " .. vim.fn.shellescape(fake.args_file),
		"printf x >> " .. vim.fn.shellescape(fake.starts_file),
		"while IFS= read -r line; do",
		"  printf '%s\\n' \"$line\" >> " .. vim.fn.shellescape(fake.events_file),
		'  case "$line" in',
		'    *\'"type":"shutdown"\'*) exit 0 ;;',
		"  esac",
		"done",
	})
	write_executable(fake_herdr, {
		"#!/bin/sh",
		"printf '%s\\n' \"$@\" >> " .. vim.fn.shellescape(herdr_calls_file),
		"if [ \"$2\" = 'split' ]; then",
		'  printf \'%s\\n\' \'{"result":{"pane":{"pane_id":"pane-fail"}}}\'',
		"  exit 0",
		"elif [ \"$2\" = 'run' ]; then",
		"  printf 'run failed' >&2",
		"  exit 9",
		"elif [ \"$2\" = 'close' ]; then",
		"  exit 0",
		"fi",
	})
	with_env(temp_dir, function()
		set_fake_paths(fake)
		vim.env.HERDR_ENV = "1"
		vim.env.HERDR_PANE_ID = "parent-fail"
		local named_path = vim.fs.joinpath(temp_dir, "herdr-run-fail.md")
		vim.fn.writefile({}, named_path)
		vim.api.nvim_buf_set_name(markdown_buf, named_path)
		assert(vim.fn.executable("herdr") == 1, "Herdr run-failure test must use the fake herdr executable from PATH")
		preview.open_browser("http://127.0.0.1:8123/page/4b")
		wait_for(function()
			local calls = vim.fn.filereadable(herdr_calls_file) == 1 and vim.fn.readfile(herdr_calls_file) or {}
			for index = 1, #calls - 2 do
				if calls[index] == "pane" and calls[index + 1] == "close" and calls[index + 2] == "pane-fail" then
					return true
				end
			end
			return false
		end, "timed out waiting for Herdr run-failure orphan close")
		local calls = vim.fn.readfile(herdr_calls_file)
		assert(
			vim.deep_equal(vim.list_slice(calls, 1, 17), {
				"pane",
				"split",
				"--pane",
				"parent-fail",
				"--direction",
				"right",
				"--ratio",
				"0.5",
				"--cwd",
				vim.fn.getcwd(),
				"--no-focus",
				"pane",
				"run",
				"pane-fail",
				"terminal-browser",
				"open",
				"http://127.0.0.1:8123/page/4b",
			}),
			"Herdr run failure must attempt split then run: " .. vim.inspect(calls)
		)
		assert(
			vim.tbl_contains(calls, "close"),
			"Herdr run failure must close the orphaned pane: " .. vim.inspect(calls)
		)
	end)
end

do
	local temp_dir = vim.fn.tempname()
	local fake = make_fake_backend(temp_dir, "http://127.0.0.1:8123/page/3")
	local ghostty_argv_file = vim.fs.joinpath(temp_dir, "osascript-argv")
	local ghostty_script_file = vim.fs.joinpath(temp_dir, "osascript-stdin")
	local ghostty_close_argv_file = vim.fs.joinpath(temp_dir, "close-argv")
	local ghostty_close_script_file = vim.fs.joinpath(temp_dir, "close-stdin")
	local ghostty_tty = vim.fs.joinpath(temp_dir, "tty")
	local fake_ps = vim.fs.joinpath(temp_dir, "ps")
	local fake_osascript = vim.fs.joinpath(temp_dir, "osascript")

	vim.fn.writefile({}, ghostty_tty)
	write_executable(fake_ps, {
		"#!/bin/sh",
		'if [ "$4" = ' .. vim.fn.shellescape(tostring(vim.fn.getpid())) .. " ]; then",
		"  printf '%s\\n' '4242 ??'",
		"else",
		"  printf '%s\\n' " .. vim.fn.shellescape("1 " .. ghostty_tty),
		"fi",
	})
	write_executable(fake_osascript, {
		"#!/bin/sh",
		"if [ \"$2\" = 'ghostty-test-pane' ]; then",
		"  /bin/cat > " .. vim.fn.shellescape(ghostty_close_script_file),
		"  printf '%s\\n' \"$@\" > " .. vim.fn.shellescape(ghostty_close_argv_file),
		"else",
		"  /bin/cat > " .. vim.fn.shellescape(ghostty_script_file),
		"  printf '%s\\n' \"$@\" > " .. vim.fn.shellescape(ghostty_argv_file),
		"  printf '%s\\n' 'ghostty-test-pane'",
		"fi",
	})

	with_env(temp_dir, function()
		set_fake_paths(fake)
		vim.env.TERM_PROGRAM = "ghostty"
		vim.env.TMUX = nil
		vim.api.nvim_set_current_buf(markdown_buf)
		assert(preview.start(markdown_buf), "Ghostty preview must start")

		wait_for(function()
			return vim.fn.filereadable(ghostty_argv_file) == 1
		end, "timed out waiting for the Ghostty split")

		local argv = vim.fn.readfile(ghostty_argv_file)
		assert(argv[1] == "-", "osascript must read the Ghostty split script from stdin")
		assert(argv[2]:match("^markdown%-preview%-%d+%-%d+$"), "Ghostty pane marker is invalid")
		assert(argv[3] == shell_command({
			fake.browser,
			"open",
			"http://127.0.0.1:8123/page/3",
			"--split-dir=right",
			"--parent-tty=" .. ghostty_tty,
		}), "Ghostty must launch terminal-browser as the split command")
		assert(argv[4] == vim.fn.getcwd(), "Ghostty split must preserve Neovim's working directory")

		local script = table.concat(vim.fn.readfile(ghostty_script_file), "\n")
		assert(script:find("configuration {command:cmdText", 1, true), "Ghostty split must use the command API")
		assert(
			not script:find("initial input", 1, true),
			"Ghostty split must not race the login shell with initial input"
		)
		local tty_contents = table.concat(vim.fn.readfile(ghostty_tty, "b"), "\n")
		assert(tty_contents:find(argv[2], 1, true), "Ghostty pane marker must be written to the parent TTY")

		preview.stop()
		wait_for(function()
			return vim.fn.filereadable(ghostty_close_argv_file) == 1
		end, "timed out waiting for the Ghostty preview pane to close")
		assert(
			vim.deep_equal(vim.fn.readfile(ghostty_close_argv_file), { "-", "ghostty-test-pane" }),
			"stop must close the Ghostty pane"
		)
		assert(
			table.concat(vim.fn.readfile(ghostty_close_script_file), "\n"):find("close term", 1, true),
			"Ghostty close script must close the matched terminal"
		)
	end)
end

if vim.env.DOTFILES_MARKDOWN_PREVIEW_E2E == "1" then
	local captured_url
	local original_open_browser = preview.open_browser
	local e2e_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[e2e_buf].filetype = "markdown"
	vim.api.nvim_buf_set_lines(e2e_buf, 0, -1, false, { "# E2E" })
	local ok, err = xpcall(function()
		preview.open_browser = function(url)
			captured_url = url
		end
		vim.g.dotfiles_markdown_preview_paths = vim.tbl_extend("force", vim.g.dotfiles_markdown_preview_paths or {}, {})
		vim.api.nvim_set_current_buf(e2e_buf)
		assert(preview.start(e2e_buf), "real backend E2E must start")
		wait_for(function()
			return captured_url ~= nil
		end, "timed out waiting for real backend ready", 10000)
		assert(captured_url:match("^http://127%.0%.0%.1:%d+/"), "real backend must return a localhost URL")
		preview.stop()
	end, debug.traceback)
	preview.open_browser = original_open_browser
	vim.api.nvim_buf_delete(e2e_buf, { force = true })
	assert(ok, err)
end

vim.api.nvim_buf_delete(markdown_buf, { force = true })
vim.api.nvim_buf_delete(big_markdown_buf, { force = true })
vim.api.nvim_buf_delete(generic_bigfile_buf, { force = true })
print("markdown preview: ok")
