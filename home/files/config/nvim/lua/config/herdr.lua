local M = {}

local function notify(message, level)
	vim.notify(message, level or vim.log.levels.INFO, { title = "Herdr" })
end

local function command_error(result, fallback)
	local message = vim.trim(result.stderr or "")
	if message == "" then
		message = vim.trim(result.stdout or "")
	end
	return message ~= "" and message or fallback
end

local function normalize_path(path)
	if not path or path == "" then
		return nil
	end
	return vim.uv.fs_realpath(path) or vim.fs.normalize(path)
end

local function path_is_within(path, root)
	path = normalize_path(path)
	root = normalize_path(root)
	if not path or not root then
		return false
	end
	return path == root or vim.startswith(path, root .. "/")
end

local function project_root(bufnr)
	local root = vim.fs.root(bufnr, ".git")
	return normalize_path(root or vim.fn.getcwd())
end

local function visual_selection()
	local bufnr = vim.api.nvim_get_current_buf()
	local mode = vim.fn.mode()
	local start_pos = vim.fn.getpos("v")
	local end_pos = vim.fn.getpos(".")

	if mode ~= "v" and mode ~= "V" and mode ~= "\22" then
		start_pos = vim.fn.getpos("'<")
		end_pos = vim.fn.getpos("'>")
		mode = vim.fn.visualmode()
	end

	local start_line, start_col = start_pos[2], start_pos[3]
	local end_line, end_col = end_pos[2], end_pos[3]
	if start_line == 0 or end_line == 0 then
		return nil, "No visual selection found"
	end

	if start_line > end_line or (start_line == end_line and start_col > end_col) then
		start_line, end_line = end_line, start_line
		start_col, end_col = end_col, start_col
	end
	if mode == "\22" and start_col > end_col then
		start_col, end_col = end_col, start_col
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
	if mode == "\22" then
		for index, line in ipairs(lines) do
			lines[index] = line:sub(start_col, end_col)
		end
	elseif mode ~= "V" then
		if #lines == 1 then
			lines[1] = lines[1]:sub(start_col, end_col)
		else
			lines[1] = lines[1]:sub(start_col)
			lines[#lines] = lines[#lines]:sub(1, end_col)
		end
	end

	local path = vim.api.nvim_buf_get_name(bufnr)
	local root = project_root(bufnr)
	local relative_path
	if path == "" then
		relative_path = "[No Name]"
	else
		relative_path = (root and vim.fs.relpath(root, path)) or vim.fn.fnamemodify(path, ":~:.")
	end

	return {
		filetype = vim.bo[bufnr].filetype,
		lines = lines,
		path = relative_path,
		root = root,
		start_line = start_line,
		end_line = end_line,
	}
end

local function code_fence(lines)
	local longest = 0
	for _, line in ipairs(lines) do
		for run in line:gmatch("`+") do
			longest = math.max(longest, #run)
		end
	end
	return string.rep("`", math.max(4, longest + 1))
end

local function context_text(selection)
	local fence = code_fence(selection.lines)
	return string.format(
		"Selection from @%s (lines %d-%d):\n\n%s%s\n%s\n%s",
		selection.path,
		selection.start_line,
		selection.end_line,
		fence,
		selection.filetype,
		table.concat(selection.lines, "\n"),
		fence
	)
end

local function choose_agent(agents, root, callback)
	local codex_agents = vim.tbl_filter(function(agent)
		return agent.agent == "codex"
	end, agents)
	local matching = vim.tbl_filter(function(agent)
		return path_is_within(agent.foreground_cwd or agent.cwd, root)
	end, codex_agents)

	if #matching == 1 then
		callback(matching[1])
		return
	end

	if #matching > 1 then
		local focused = vim.tbl_filter(function(agent)
			return agent.focused
		end, matching)
		if #focused == 1 then
			callback(focused[1])
			return
		end
	end

	local candidates = #matching > 0 and matching or codex_agents
	if #candidates == 0 then
		notify("No Codex agent is running in Herdr", vim.log.levels.ERROR)
		return
	end

	vim.ui.select(candidates, {
		prompt = #matching == 0 and "No Codex agent matches this repository; choose one:" or "Choose a Codex agent:",
		format_item = function(agent)
			local cwd = agent.foreground_cwd or agent.cwd or "unknown cwd"
			return string.format("%s  %s", agent.pane_id, cwd)
		end,
	}, function(agent)
		if agent then
			callback(agent)
		end
	end)
end

local function with_agent(root, callback)
	vim.system({ "herdr", "agent", "list" }, { text = true }, function(result)
		vim.schedule(function()
			if result.code ~= 0 then
				notify(command_error(result, "Unable to list Herdr agents"), vim.log.levels.ERROR)
				return
			end

			local ok, response = pcall(vim.json.decode, result.stdout or "")
			local agents = ok and type(response) == "table" and response.result and response.result.agents
			if type(agents) ~= "table" then
				notify("Herdr returned an invalid agent list", vim.log.levels.ERROR)
				return
			end

			choose_agent(agents, root, callback)
		end)
	end)
end

local function send_prompt(agent, text)
	vim.system({ "herdr", "agent", "prompt", agent.pane_id, text }, { text = true }, function(result)
		vim.schedule(function()
			if result.code ~= 0 then
				notify(command_error(result, "Unable to contact Herdr"), vim.log.levels.ERROR)
				return
			end

			notify("Selection sent to Codex")
		end)
	end)
end

function M.prompt_selection()
	if vim.fn.executable("herdr") ~= 1 then
		notify("The herdr command is not available", vim.log.levels.ERROR)
		return
	end

	local selection, err = visual_selection()
	if not selection then
		notify(err, vim.log.levels.WARN)
		return
	end

	vim.ui.input({ prompt = "Ask Herdr Codex about the selection: " }, function(question)
		if not question or vim.trim(question) == "" then
			return
		end

		local prompt = string.format("%s\n\nQuestion:\n%s", context_text(selection), question)
		with_agent(selection.root, function(agent)
			send_prompt(agent, prompt)
		end)
	end)
end

return M
