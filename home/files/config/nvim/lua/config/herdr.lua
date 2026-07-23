local M = {}

local agent_names = {
	claude = "Claude Code",
	codex = "Codex",
}
local selected_agents = {}

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

local function agent_name(agent)
	return agent_names[agent.agent] or agent.agent or "AI agent"
end

local function session_key(agent)
	local session = agent.agent_session
	if type(session) ~= "table" then
		return nil
	end

	return table.concat({ session.agent or "", session.source or "", session.kind or "", session.value or "" }, "\0")
end

local function remember_agent(root, agent)
	selected_agents[root] = {
		pane_id = agent.pane_id,
		session_key = session_key(agent),
	}
end

local function cached_agent(agents, root)
	local selected = selected_agents[root]
	if not selected then
		return nil
	end

	for _, agent in ipairs(agents) do
		if agent.pane_id == selected.pane_id then
			local current_session = session_key(agent)
			if not selected.session_key or not current_session or selected.session_key == current_session then
				return agent
			end
			break
		end
	end

	selected_agents[root] = nil
	return nil
end

local function agent_label(agent)
	local focus = agent.focused and "●" or " "
	local location = agent.foreground_cwd or agent.cwd or "unknown cwd"
	local status = agent.agent_status or "unknown"
	local tab = agent.tab_id or agent.pane_id or "unknown pane"
	local pane = agent.pane_id and agent.pane_id ~= tab and " / " .. agent.pane_id or ""
	return string.format("%s %s · %s%s · %s · %s", focus, agent_name(agent), tab, pane, status, location)
end

local function list_agents(callback)
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

			local supported = vim.tbl_filter(function(agent)
				return type(agent) == "table" and agent_names[agent.agent] ~= nil and type(agent.pane_id) == "string"
			end, agents)
			callback(supported)
		end)
	end)
end

local function choose_agent(agents, root, force, callback)
	if not force then
		local selected = cached_agent(agents, root)
		if selected then
			callback(selected)
			return
		end
	end

	local matching = vim.tbl_filter(function(agent)
		return path_is_within(agent.foreground_cwd or agent.cwd, root)
	end, agents)
	local candidates = #matching > 0 and matching or agents
	if #candidates == 0 then
		notify("No Codex or Claude Code agent is running in Herdr", vim.log.levels.ERROR)
		return
	end

	table.sort(candidates, function(left, right)
		local left_focused = left.focused == true
		local right_focused = right.focused == true
		if left_focused ~= right_focused then
			return left_focused
		end
		if left.agent ~= right.agent then
			return left.agent < right.agent
		end
		return left.pane_id < right.pane_id
	end)

	if #matching == 1 and not force then
		remember_agent(root, matching[1])
		callback(matching[1])
		return
	end

	local prompt = #matching == 0 and "No agent matches this repository; choose a Herdr agent:"
		or "Choose a Herdr agent:"
	vim.ui.select(candidates, {
		prompt = prompt,
		format_item = agent_label,
	}, function(agent)
		if agent then
			remember_agent(root, agent)
			callback(agent)
		end
	end)
end

local function with_agent(root, force, callback)
	list_agents(function(agents)
		choose_agent(agents, root, force, callback)
	end)
end

local function insert_newline(win)
	local row, column = unpack(vim.api.nvim_win_get_cursor(win.win))
	vim.api.nvim_buf_set_text(win.buf, row - 1, column, row - 1, column, { "", "" })
	vim.api.nvim_win_set_cursor(win.win, { row + 1, 0 })
end

local function ask_question(agent, callback)
	local opts = {
		prompt = string.format(
			"Ask %s · %s  (Enter send · S-Enter/C-J newline)",
			agent_name(agent),
			agent.tab_id or agent.pane_id
		),
		expand = false,
		win = {
			height = 7,
			width = 80,
			actions = {
				insert_newline = insert_newline,
			},
			keys = {
				i_ctrl_j = { "<c-j>", "insert_newline", mode = "i" },
				i_down = false,
				i_s_cr = { "<s-cr>", "insert_newline", mode = "i" },
				i_up = false,
			},
		},
	}
	local ok, snacks = pcall(require, "snacks")
	if ok then
		snacks.input(opts, callback)
		return
	end

	vim.ui.input({ prompt = opts.prompt }, callback)
end

local function send_prompt(agent, text)
	vim.system({ "herdr", "agent", "prompt", agent.pane_id, text }, { text = true }, function(result)
		vim.schedule(function()
			if result.code ~= 0 then
				notify(command_error(result, "Unable to contact Herdr"), vim.log.levels.ERROR)
				return
			end

			notify(string.format("Selection sent to %s (%s)", agent_name(agent), agent.tab_id or agent.pane_id))
		end)
	end)
end

function M.select_agent()
	if vim.fn.executable("herdr") ~= 1 then
		notify("The herdr command is not available", vim.log.levels.ERROR)
		return
	end

	local root = project_root(vim.api.nvim_get_current_buf())
	with_agent(root, true, function(agent)
		notify(string.format("Using %s (%s) for this Neovim session", agent_name(agent), agent.tab_id or agent.pane_id))
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

	with_agent(selection.root, false, function(agent)
		ask_question(agent, function(question)
			if not question or vim.trim(question) == "" then
				return
			end

			local prompt = string.format("%s\n\nQuestion:\n%s", context_text(selection), question)
			send_prompt(agent, prompt)
		end)
	end)
end

return M
