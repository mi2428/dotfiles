local M = {}
local ghostty_browser_pane
local ghostty_browser_generation = 0

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

local function notify_error(message)
	vim.schedule(function()
		vim.notify(message, vim.log.levels.ERROR)
	end)
end

local function current_buffer(bufnr)
	bufnr = bufnr or 0
	return bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
end

local function open_in_herdr(url)
	local parent = vim.env.HERDR_PANE_ID
	if vim.env.HERDR_ENV ~= "1" or not parent or parent == "" or vim.fn.executable("herdr") ~= 1 then
		return false
	end

	-- Ghostty title probing cannot identify a busy Herdr TUI pane, so split by its stable pane ID.
	vim.system({
		"herdr",
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
			notify_error("Failed to create a browser pane: " .. vim.trim(result.stderr))
			return
		end

		local ok, payload = pcall(vim.json.decode, result.stdout)
		local pane = ok and payload.result and payload.result.pane and payload.result.pane.pane_id or nil
		if not pane then
			notify_error("Failed to read the browser pane ID from Herdr")
			return
		end

		vim.system({ "herdr", "pane", "run", pane, "terminal-browser", "open", url }, { text = true }, function(run)
			if run.code ~= 0 then
				notify_error("Failed to start terminal-browser in Herdr: " .. vim.trim(run.stderr))
			end
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

local function shell_command(argv)
	return table.concat(
		vim.tbl_map(function(arg)
			return vim.fn.shellescape(arg)
		end, argv),
		" "
	)
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
			notify_error("Failed to mark the Ghostty pane at " .. tty)
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
							notify_error("Ghostty did not return the Markdown preview pane ID")
						elseif generation == ghostty_browser_generation then
							ghostty_browser_pane = pane
						else
							close_ghostty_pane(pane)
						end
						return
					end
					vim.schedule(function()
						if attempts < 6 then
							split()
							return
						end
						local message = vim.trim(result.stderr)
						notify_error(
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
	if open_in_ghostty(url) then
		return
	end

	local errors = {}
	local job = vim.fn.jobstart({ "terminal-browser", "open", url, "--split", "right", "--size", "0.5" }, {
		detach = true,
		stderr_buffered = true,
		on_stderr = function(_, data)
			for _, line in ipairs(data or {}) do
				if line ~= "" then
					errors[#errors + 1] = line
				end
			end
		end,
		on_exit = function(_, code)
			if code ~= 0 then
				vim.schedule(function()
					local message = #errors > 0 and table.concat(errors, "\n") or ("exit code %d"):format(code)
					if not (message:find("could not find this pane in Ghostty", 1, true) and open_in_herdr(url)) then
						vim.notify("terminal-browser failed: " .. message, vim.log.levels.ERROR)
					end
				end)
			end
		end,
	})
	if job <= 0 then
		vim.notify(("Failed to start terminal-browser (code %d)"):format(job), vim.log.levels.ERROR)
	end
end

function M.toggle()
	if not M.is_markdown_buffer() then
		vim.notify("Markdown preview is only available in Markdown buffers", vim.log.levels.WARN)
		return
	end

	if vim.b.MarkdownPreviewToggleBool == 1 then
		close_ghostty_browser()
	end
	vim.fn["mkdp#util#toggle_preview"]()
end

function M.setup()
	local config_dir = vim.fn.stdpath("config")

	vim.g.mkdp_browserfunc = "DotfilesMarkdownPreviewBrowser"
	vim.g.mkdp_markdown_css = vim.fs.joinpath(config_dir, "assets", "markdown-preview.css")
	vim.g.mkdp_highlight_css = vim.fs.joinpath(config_dir, "assets", "markdown-preview-highlight.css")
	vim.g.mkdp_theme = "dark"
	vim.g.mkdp_open_to_the_world = 0
	vim.g.mkdp_open_ip = "127.0.0.1"
	vim.g.mkdp_auto_start = 0
	vim.g.mkdp_auto_close = 0
	vim.g.mkdp_combine_preview = 1
	vim.g.mkdp_combine_preview_auto_refresh = 1
	vim.g.mkdp_refresh_slow = 0
	vim.g.mkdp_preview_options = {
		mkit = {},
		katex = {},
		uml = {},
		maid = { theme = "dark" },
		disable_sync_scroll = 0,
		sync_scroll_type = "middle",
		hide_yaml_meta = 1,
		sequence_diagrams = {},
		flowchart_diagrams = {},
		toc = {},
		content_editable = false,
		disable_filename = 0,
	}
	vim.g.mkdp_filetypes = { "markdown" }

	_G.DotfilesMarkdownPreviewBrowser = M.open_browser
	vim.cmd([[
function! DotfilesMarkdownPreviewBrowser(url) abort
  call v:lua.DotfilesMarkdownPreviewBrowser(a:url)
endfunction
]])
end

return M
