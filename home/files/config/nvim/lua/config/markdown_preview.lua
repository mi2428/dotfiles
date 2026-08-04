local M = {}

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
