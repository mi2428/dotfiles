local M = {}

local agent_names = {
	claude = "Claude Code",
	codex = "Codex",
	opencode = "OpenCode",
}

local worker_token = "agent_layout_worker"

local catppuccin_mocha = {
	red = "#f38ba8",
	peach = "#fab387",
	yellow = "#f9e2af",
	green = "#a6e3a1",
	teal = "#94e2d5",
	blue = "#89b4fa",
	lavender = "#b4befe",
	mauve = "#cba6f7",
	overlay1 = "#7f849c",
	overlay0 = "#6c7086",
}

local function setup_highlights()
	local highlights = {
		HerdrMarker = { fg = catppuccin_mocha.mauve, bold = true },
		HerdrAgent = { fg = catppuccin_mocha.blue, bold = true },
		HerdrStatus = { fg = catppuccin_mocha.overlay1 },
		HerdrStatusIdle = { fg = catppuccin_mocha.green },
		HerdrStatusWorking = { fg = catppuccin_mocha.yellow },
		HerdrStatusDone = { fg = catppuccin_mocha.blue },
		HerdrStatusBlocked = { fg = catppuccin_mocha.red },
		HerdrWorkspace = { fg = catppuccin_mocha.teal },
		HerdrBranch = { fg = catppuccin_mocha.peach },
		HerdrTitle = { fg = catppuccin_mocha.lavender },
		HerdrSeparator = { fg = catppuccin_mocha.overlay0 },
	}
	for group, opts in pairs(highlights) do
		vim.api.nvim_set_hl(0, group, opts)
	end
end

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

local function display_path(path)
	if not path or path == "" then
		return nil
	end
	return vim.fn.fnamemodify(path, ":~:.")
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

local function buffer_info(bufnr)
	local path = vim.api.nvim_buf_get_name(bufnr)
	if path == "" then
		return string.format("buf:%d", bufnr), "[No Name]"
	end

	local root = project_root(bufnr)
	local absolute = normalize_path(path) or path
	local display = (root and absolute and path_is_within(absolute, root) and vim.fs.relpath(root, absolute))
		or vim.fn.fnamemodify(path, ":~:.")
	return absolute, display
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

	local cache_key, display = buffer_info(bufnr)
	return {
		cache_key = cache_key,
		display_path = display,
		filetype = vim.bo[bufnr].filetype,
		lines = lines,
		root = project_root(bufnr),
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
		selection.display_path,
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

local function is_destination_agent(agent)
	return type(agent) == "table"
		and agent_names[agent.agent] ~= nil
		and type(agent.pane_id) == "string"
		and not (type(agent.tokens) == "table" and agent.tokens[worker_token] == "1")
end

local function session_key(agent)
	local session = agent.agent_session
	if type(session) ~= "table" then
		return nil
	end

	return table.concat({ session.agent or "", session.source or "", session.kind or "", session.value or "" }, "\0")
end

local function agent_signature(agent)
	return {
		agent = agent.agent,
		herdr_socket_path = normalize_path(agent.herdr_socket_path or vim.env.HERDR_SOCKET_PATH),
		pane_id = agent.pane_id,
		tab_id = agent.tab_id,
		workspace_id = agent.workspace_id,
		terminal_id = agent.terminal_id,
		cwd = normalize_path(agent.cwd) or agent.cwd,
		foreground_cwd = normalize_path(agent.foreground_cwd) or agent.foreground_cwd,
		session_key = session_key(agent),
	}
end

local function same_signature(left, right)
	if not left or not right then
		return false
	end
	for _, field in ipairs({
		"agent",
		"herdr_socket_path",
		"pane_id",
		"tab_id",
		"workspace_id",
		"terminal_id",
		"cwd",
		"foreground_cwd",
		"session_key",
	}) do
		if left[field] ~= right[field] then
			return false
		end
	end
	return true
end

local function remember_agent(file_key, agent)
	selected_agents[file_key] = agent_signature(agent)
end

local function cached_agent(agents, file_key)
	local selected = selected_agents[file_key]
	if not selected then
		return nil
	end

	for _, agent in ipairs(agents) do
		if same_signature(agent_signature(agent), selected) then
			return agent
		end
	end

	selected_agents[file_key] = nil
	return nil
end

local function run_json(command, fallback)
	local result = vim.system(command, { text = true }):wait()
	if result.code ~= 0 then
		return nil, command_error(result, fallback)
	end

	local ok, decoded = pcall(vim.json.decode, result.stdout or "")
	if not ok or type(decoded) ~= "table" then
		return nil, fallback
	end

	return decoded
end

local function item_table(decoded, keys)
	local current = decoded
	for _, key in ipairs(keys) do
		if type(current) ~= "table" then
			return nil
		end
		current = current[key]
	end
	return type(current) == "table" and current or nil
end

local function load_metadata()
	local metadata = {
		session_name = "default",
		session_socket_path = nil,
		workspaces = {},
		tabs = {},
	}
	local branch_cache = {}

	function metadata.branch_for_cwd(cwd)
		if not cwd or cwd == "" then
			return nil
		end

		local key = normalize_path(cwd) or cwd
		if branch_cache[key] ~= nil then
			return branch_cache[key] or nil
		end

		local result = vim.system({ "git", "-C", cwd, "branch", "--show-current" }, { text = true }):wait()
		if result.code ~= 0 then
			branch_cache[key] = false
			return nil
		end

		local branch = vim.trim(result.stdout or "")
		branch_cache[key] = branch ~= "" and branch or false
		return branch_cache[key] or nil
	end

	local sessions, session_err = run_json({ "herdr", "session", "list", "--json" }, "Unable to list Herdr sessions")
	if sessions then
		local session_list = item_table(sessions, { "sessions" }) or {}
		local default_session = nil
		local matched_session = nil
		local env_socket = vim.env.HERDR_SOCKET_PATH
		for _, session in ipairs(session_list) do
			if type(session) == "table" then
				if session.default then
					default_session = default_session or session
				end
				if env_socket and session.socket_path == env_socket then
					matched_session = session
					break
				end
			end
		end
		local current = matched_session or default_session or session_list[1]
		if type(current) == "table" then
			metadata.session_name = current.name or (current.default and "default") or metadata.session_name
			metadata.session_socket_path = current.socket_path
		end
	elseif session_err then
		notify(session_err, vim.log.levels.WARN)
	end

	local workspaces, workspace_err = run_json({ "herdr", "workspace", "list" }, "Unable to list Herdr workspaces")
	if workspaces then
		for _, workspace in
			ipairs(item_table(workspaces, { "result", "workspaces" }) or item_table(workspaces, { "workspaces" }) or {})
		do
			if type(workspace) == "table" and workspace.workspace_id then
				metadata.workspaces[workspace.workspace_id] = workspace
			end
		end
	elseif workspace_err then
		notify(workspace_err, vim.log.levels.WARN)
	end

	local tabs, tab_err = run_json({ "herdr", "tab", "list" }, "Unable to list Herdr tabs")
	if tabs then
		for _, tab in ipairs(item_table(tabs, { "result", "tabs" }) or item_table(tabs, { "tabs" }) or {}) do
			if type(tab) == "table" and tab.tab_id then
				metadata.tabs[tab.tab_id] = tab
			end
		end
	elseif tab_err then
		notify(tab_err, vim.log.levels.WARN)
	end

	return metadata
end

local function load_agents()
	local response, err = run_json({ "herdr", "agent", "list" }, "Unable to list Herdr agents")
	if not response then
		return nil, err
	end

	local agents = item_table(response, { "result", "agents" }) or item_table(response, { "agents" })
	if type(agents) ~= "table" then
		return nil, "Herdr returned an invalid agent list"
	end

	local supported = vim.tbl_filter(function(agent)
		return is_destination_agent(agent)
	end, agents)

	return supported
end

local function load_agent_state()
	local agents, err = load_agents()
	if not agents then
		return nil, err
	end
	return {
		agents = agents,
		metadata = load_metadata(),
	}
end

local function session_label(metadata)
	local name = metadata and metadata.session_name or "default"
	return "session " .. name
end

local function workspace_label(agent, metadata)
	local workspace = metadata and metadata.workspaces and metadata.workspaces[agent.workspace_id] or nil
	if type(workspace) == "table" then
		local label = workspace.label or workspace.workspace_id or agent.workspace_id or "unknown"
		local number = workspace.number and string.format("#%s", workspace.number) or nil
		local parts = { "workspace", label }
		if number then
			parts[#parts + 1] = number
		end
		return table.concat(parts, " ")
	end
	return agent.workspace_id and ("workspace " .. agent.workspace_id) or nil
end

local function tab_label(agent, metadata)
	local tab = metadata and metadata.tabs and metadata.tabs[agent.tab_id] or nil
	if type(tab) == "table" then
		local label = tab.label or tab.tab_id or agent.tab_id or "unknown"
		local number = tab.number and string.format("#%s", tab.number) or nil
		local parts = { "tab", label }
		if number then
			parts[#parts + 1] = number
		end
		return table.concat(parts, " ")
	end
	return agent.tab_id and ("tab " .. agent.tab_id) or nil
end

local function agent_location(agent, metadata)
	local cwd = agent.foreground_cwd or agent.cwd
	if not cwd or cwd == "" then
		return nil
	end

	local location = display_path(cwd) or cwd
	local branch = metadata and metadata.branch_for_cwd and metadata.branch_for_cwd(cwd) or nil
	if branch then
		return string.format("path %s @ %s", location, branch)
	end
	return "path " .. location
end

local function agent_context(agent, metadata)
	local context = {}
	local location = agent_location(agent, metadata)
	if location then
		context[#context + 1] = location
	end
	context[#context + 1] = session_label(metadata)
	local workspace = workspace_label(agent, metadata)
	if workspace then
		context[#context + 1] = workspace
	end
	local tab = tab_label(agent, metadata)
	if tab then
		context[#context + 1] = tab
	end
	if agent.terminal_title_stripped and vim.trim(agent.terminal_title_stripped) ~= "" then
		context[#context + 1] = string.format('title "%s"', agent.terminal_title_stripped)
	end
	if agent.pane_id then
		context[#context + 1] = "pane " .. agent.pane_id
	end
	if agent.agent_status then
		context[#context + 1] = agent.agent_status
	end
	return table.concat(context, " · ")
end

local function agent_marker(agent, remembered)
	local prefix = agent.focused and "*" or " "
	if remembered and same_signature(agent_signature(agent), remembered) then
		prefix = ">"
	end
	return prefix
end

local function agent_label(agent, metadata, remembered)
	local parts = { agent_marker(agent, remembered) .. " " .. agent_name(agent) }
	local context = agent_context(agent, metadata)
	if context ~= "" then
		parts[#parts + 1] = context
	end
	return table.concat(parts, " · ")
end

local function agent_summary(agent, metadata, remembered, supports_chunks)
	local workspace = metadata and metadata.workspaces and metadata.workspaces[agent.workspace_id] or nil
	local tab = metadata and metadata.tabs and metadata.tabs[agent.tab_id] or nil
	local workspace_name = type(workspace) == "table" and (workspace.label or workspace.workspace_id)
		or agent.workspace_id
	local tab_name = type(tab) == "table" and (tab.label or tab.tab_id) or agent.tab_id
	local location
	if workspace_name or tab_name then
		location = workspace_name or "?"
		if type(workspace) == "table" and workspace.number then
			location = string.format("%s #%s", location, workspace.number)
		end
		if tab_name then
			location = location .. " / " .. tab_name
			if type(tab) == "table" and tab.number then
				location = string.format("%s #%s", location, tab.number)
			end
		end
	end

	local cwd = agent.foreground_cwd or agent.cwd
	local branch = metadata and metadata.branch_for_cwd and metadata.branch_for_cwd(cwd) or nil
	local title = agent.terminal_title_stripped and vim.trim(agent.terminal_title_stripped) or nil

	local fields = {
		{ text = location, hl = "HerdrWorkspace" },
		{ text = branch, hl = "HerdrBranch" },
		{ text = title ~= "" and title or nil, hl = "HerdrTitle" },
	}
	local marker = agent_marker(agent, remembered)
	local status_highlights = {
		idle = "HerdrStatusIdle",
		working = "HerdrStatusWorking",
		done = "HerdrStatusDone",
		blocked = "HerdrStatusBlocked",
		error = "HerdrStatusBlocked",
	}
	local status_hl = status_highlights[agent.agent_status] or "HerdrStatus"

	if supports_chunks then
		local chunks = {
			{ marker .. " ", "HerdrMarker" },
			{ agent_name(agent), "HerdrAgent" },
		}
		if agent.agent_status then
			chunks[#chunks + 1] = { " [" }
			chunks[#chunks + 1] = { agent.agent_status, status_hl }
			chunks[#chunks + 1] = { "]" }
		end
		for _, field in ipairs(fields) do
			if field.text then
				chunks[#chunks + 1] = { " · ", "HerdrSeparator" }
				chunks[#chunks + 1] = { field.text, field.hl }
			end
		end
		return chunks
	end

	local parts = { marker .. " " .. agent_name(agent) }
	if agent.agent_status then
		parts[1] = string.format("%s [%s]", parts[1], agent.agent_status)
	end
	for _, field in ipairs(fields) do
		if field.text then
			parts[#parts + 1] = field.text
		end
	end
	return table.concat(parts, " · ")
end

local function choose_sort_key(agent, metadata)
	local workspace = metadata and metadata.workspaces and metadata.workspaces[agent.workspace_id] or nil
	local tab = metadata and metadata.tabs and metadata.tabs[agent.tab_id] or nil
	return {
		focused = agent.focused == true,
		agent = agent.agent or "",
		workspace_number = type(workspace) == "table" and workspace.number or math.huge,
		tab_number = type(tab) == "table" and tab.number or math.huge,
		pane_id = agent.pane_id or "",
	}
end

local function select_destination(items, opts, on_choice)
	local ok, snacks = pcall(require, "snacks")
	if ok and snacks.picker and type(snacks.picker.select) == "function" then
		local snacks_opts = vim.tbl_extend("force", {}, opts)
		snacks_opts.format_item = opts.snacks_format_item or opts.format_item
		snacks_opts.snacks_format_item = nil
		snacks.picker.select(items, snacks_opts, on_choice)
		return
	end

	local fallback_opts = vim.tbl_extend("force", {}, opts)
	fallback_opts.snacks = nil
	fallback_opts.snacks_format_item = nil
	vim.ui.select(items, fallback_opts, on_choice)
end

local function choose_agent(agents, file_key, file_label, root, metadata, callback)
	agents = vim.tbl_filter(is_destination_agent, agents)
	cached_agent(agents, file_key)
	local remembered = selected_agents[file_key]
	local matching = vim.tbl_filter(function(agent)
		return path_is_within(agent.foreground_cwd or agent.cwd, root)
	end, agents)
	local candidates = #matching > 0 and matching or agents
	if #candidates == 0 then
		notify("No supported AI agent is running in Herdr", vim.log.levels.ERROR)
		return
	end
	setup_highlights()

	table.sort(candidates, function(left, right)
		local left_remembered = remembered and same_signature(agent_signature(left), remembered)
		local right_remembered = remembered and same_signature(agent_signature(right), remembered)
		if left_remembered ~= right_remembered then
			return left_remembered
		end

		local left_key = choose_sort_key(left, metadata)
		local right_key = choose_sort_key(right, metadata)
		if left_key.focused ~= right_key.focused then
			return left_key.focused
		end
		if left_key.workspace_number ~= right_key.workspace_number then
			return left_key.workspace_number < right_key.workspace_number
		end
		if left_key.tab_number ~= right_key.tab_number then
			return left_key.tab_number < right_key.tab_number
		end
		if left_key.agent ~= right_key.agent then
			return left_key.agent < right_key.agent
		end
		return left_key.pane_id < right_key.pane_id
	end)

	select_destination(candidates, {
		prompt = string.format("Choose a Herdr agent for %s:", file_label),
		format_item = function(agent)
			return agent_label(agent, metadata, remembered)
		end,
		snacks_format_item = function(agent, supports_chunks)
			return agent_summary(agent, metadata, remembered, supports_chunks)
		end,
		snacks = {
			layout = {
				hidden = { "preview" },
				layout = {
					backdrop = false,
					width = 0.75,
					min_width = 80,
					max_width = 140,
					height = 0.4,
					min_height = 2,
					box = "vertical",
					border = true,
					title = "{title}",
					title_pos = "center",
					{ win = "input", height = 1, border = "bottom" },
					{ win = "list", border = "none" },
				},
			},
		},
	}, function(agent)
		if agent then
			remember_agent(file_key, agent)
			callback(agent)
		end
	end)
end

local function with_agent(file_key, file_label, root, callback)
	local state, err = load_agent_state()
	if not state then
		notify(err or "Unable to load Herdr state", vim.log.levels.ERROR)
		return
	end

	choose_agent(state.agents, file_key, file_label, root, state.metadata, callback)
end

local function insert_newline(win)
	local row, column = unpack(vim.api.nvim_win_get_cursor(win.win))
	vim.api.nvim_buf_set_text(win.buf, row - 1, column, row - 1, column, { "", "" })
	vim.api.nvim_win_set_cursor(win.win, { row + 1, 0 })
end

local function delete_before_cursor(win)
	local row, column = unpack(vim.api.nvim_win_get_cursor(win.win))
	local line = vim.api.nvim_buf_get_lines(win.buf, row - 1, row, false)[1]
	if column > 0 then
		local positions = vim.str_utf_pos(line:sub(1, column))
		local previous_column = positions[#positions] - 1
		vim.api.nvim_buf_set_text(win.buf, row - 1, previous_column, row - 1, column, {})
		vim.api.nvim_win_set_cursor(win.win, { row, previous_column })
		return
	end
	if row == 1 then
		return
	end

	local previous = vim.api.nvim_buf_get_lines(win.buf, row - 2, row - 1, false)[1]
	vim.api.nvim_buf_set_text(win.buf, row - 2, #previous, row - 1, 0, {})
	vim.api.nvim_win_set_cursor(win.win, { row - 1, #previous })
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
				delete_before_cursor = delete_before_cursor,
				insert_newline = insert_newline,
			},
			keys = {
				i_bs = { "<bs>", "delete_before_cursor", mode = "i" },
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

local function resolve_live_agent(target)
	local agents, err = load_agents()
	if not agents then
		return nil, err
	end

	for _, agent in ipairs(agents) do
		if same_signature(agent_signature(agent), target) then
			return agent
		end
	end

	return nil, "The selected Herdr agent changed or disappeared before send"
end

local function send_prompt(target, text)
	local agent, err = resolve_live_agent(target)
	if not agent then
		notify(err or "The selected Herdr agent changed or disappeared before send", vim.log.levels.ERROR)
		return false
	end

	local result = vim.system({ "herdr", "agent", "prompt", agent.pane_id, text }, { text = true }):wait()
	if result.code ~= 0 then
		notify(command_error(result, "Unable to contact Herdr"), vim.log.levels.ERROR)
		return false
	end

	notify(string.format("Selection sent to %s (%s)", agent_name(agent), agent.tab_id or agent.pane_id))
	return true
end

function M.select_agent()
	if vim.fn.executable("herdr") ~= 1 then
		notify("The herdr command is not available", vim.log.levels.ERROR)
		return
	end

	local bufnr = vim.api.nvim_get_current_buf()
	local root = project_root(bufnr)
	local file_key, file_label = buffer_info(bufnr)
	with_agent(file_key, file_label, root, function(agent)
		notify(string.format("Using %s (%s) for this file", agent_name(agent), agent.tab_id or agent.pane_id))
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

	with_agent(selection.cache_key, selection.display_path, selection.root, function(agent)
		local target = agent_signature(agent)
		ask_question(agent, function(question)
			if not question or vim.trim(question) == "" then
				return
			end

			local prompt = string.format("%s\n\nQuestion:\n%s", context_text(selection), question)
			send_prompt(target, prompt)
		end)
	end)
end

M._test = {
	agent_context = agent_context,
	agent_label = agent_label,
	agent_summary = agent_summary,
	agent_signature = agent_signature,
	is_destination_agent = is_destination_agent,
	buffer_info = buffer_info,
	cached_agent = cached_agent,
	choose_agent = choose_agent,
	context_text = context_text,
	load_agent_state = load_agent_state,
	load_metadata = load_metadata,
	remember_agent = remember_agent,
	resolve_live_agent = resolve_live_agent,
	send_prompt = send_prompt,
	reset = function()
		selected_agents = {}
	end,
}

return M
