local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
local home = assert(vim.env.HOME, "HOME is required")
local herdr_root = vim.fs.joinpath(home, ".config/herdr")
local default_socket = vim.fs.joinpath(herdr_root, "herdr.sock")
local quick_session_dir = vim.fs.joinpath(herdr_root, "sessions/quick")
local quick_socket = vim.fs.joinpath(quick_session_dir, "herdr.sock")
local other_project = vim.fs.joinpath(vim.env.TMPDIR or "/tmp", "herdr-test/vpg-autoscaler")

vim.opt.runtimepath:prepend(nvim_root)
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")

vim.env.HERDR_SOCKET_PATH = quick_socket

local notifications = {}
vim.notify = function(message, level, opts)
	notifications[#notifications + 1] = { message = message, level = level, opts = opts }
end

local herdr = require("config.herdr")
herdr._test.reset()

local function json(value)
	return vim.json.encode(value)
end

local agent_a = {
	agent = "codex",
	agent_status = "working",
	cwd = dotfiles_root,
	focused = false,
	foreground_cwd = dotfiles_root,
	pane_id = "w1S:p1",
	tab_id = "w1S:t3",
	terminal_id = "term_a",
	terminal_title_stripped = "OC | Neovim leader h送信先ポップアップ改善と記憶機能",
	workspace_id = "w1S",
	agent_session = { agent = "codex", kind = "id", source = "herdr:codex", value = "ses_aaa" },
}

local agent_b = {
	agent = "opencode",
	agent_status = "idle",
	cwd = other_project,
	focused = true,
	foreground_cwd = other_project,
	pane_id = "w1R:p1",
	tab_id = "w1R:t1",
	terminal_id = "term_b",
	terminal_title_stripped = "OC | vpg autoscaler audit",
	workspace_id = "w1R",
}

local worker_a = {
	agent = "opencode",
	agent_status = "working",
	cwd = dotfiles_root,
	focused = false,
	foreground_cwd = dotfiles_root,
	pane_id = "w1S:p2",
	tab_id = "w1S:t3",
	terminal_id = "term_worker_a",
	terminal_title_stripped = "worker for dotfiles supervisor",
	tokens = { agent_layout_worker = "1" },
	workspace_id = "w1S",
}

local worker_b = {
	agent = "codex",
	agent_status = "idle",
	cwd = other_project,
	focused = false,
	foreground_cwd = other_project,
	pane_id = "w1R:p2",
	tab_id = "w1R:t1",
	terminal_id = "term_worker_b",
	terminal_title_stripped = "worker for autoscaler supervisor",
	tokens = { agent_layout_worker = "1" },
	workspace_id = "w1R",
}

local branch_by_cwd = {
	[dotfiles_root] = "main",
	[other_project] = "feature/autoscaler",
}

local metadata_ok = true
local live_agents = { agent_a, worker_a, agent_b, worker_b }
local prompt_calls = {}
local system_calls = {}
local select_calls = {}

local function metadata_payload()
	return {
		sessions = {
			{
				default = true,
				name = "default",
				running = true,
				session_dir = herdr_root,
				socket_path = default_socket,
			},
			{
				default = false,
				name = "quick",
				running = true,
				session_dir = quick_session_dir,
				socket_path = quick_socket,
			},
		},
		workspaces = {
			{
				active_tab_id = "w1R:t1",
				agent_status = "idle",
				focused = false,
				label = "vpg-autoscaler",
				number = 2,
				pane_count = 1,
				tab_count = 1,
				workspace_id = "w1R",
			},
			{
				active_tab_id = "w1S:t3",
				agent_status = "working",
				focused = false,
				label = "dotfiles",
				number = 3,
				pane_count = 2,
				tab_count = 2,
				workspace_id = "w1S",
			},
		},
		tabs = {
			{
				agent_status = "working",
				focused = false,
				label = "agents:t1",
				number = 2,
				pane_count = 1,
				tab_id = "w1R:t1",
				workspace_id = "w1R",
			},
			{
				agent_status = "working",
				focused = false,
				label = "agents:t3",
				number = 3,
				pane_count = 1,
				tab_id = "w1S:t3",
				workspace_id = "w1S",
			},
		},
	}
end

local function result_for(command)
	local key = table.concat(command, "\0")
	if command[1] == "git" and command[2] == "-C" and command[4] == "branch" then
		return { code = 0, stdout = (branch_by_cwd[command[3]] or "") .. "\n", stderr = "" }
	end
	if key == "herdr\0session\0list\0--json" then
		if not metadata_ok then
			return { code = 1, stdout = "", stderr = "session metadata unavailable" }
		end
		return { code = 0, stdout = json({ sessions = metadata_payload().sessions }), stderr = "" }
	end
	if key == "herdr\0workspace\0list" then
		if not metadata_ok then
			return { code = 1, stdout = "", stderr = "workspace metadata unavailable" }
		end
		return {
			code = 0,
			stdout = json({
				id = "cli:workspace:list",
				result = { type = "workspace_list", workspaces = metadata_payload().workspaces },
			}),
			stderr = "",
		}
	end
	if key == "herdr\0tab\0list" then
		if not metadata_ok then
			return { code = 1, stdout = "", stderr = "tab metadata unavailable" }
		end
		return {
			code = 0,
			stdout = json({ id = "cli:tab:list", result = { tabs = metadata_payload().tabs, type = "tab_list" } }),
			stderr = "",
		}
	end
	if key == "herdr\0agent\0list" then
		return { code = 0, stdout = json({ id = "cli:agent:list", result = { agents = live_agents } }), stderr = "" }
	end
	if command[1] == "herdr" and command[2] == "agent" and command[3] == "prompt" then
		prompt_calls[#prompt_calls + 1] = { pane_id = command[4], text = command[5] }
		return { code = 0, stdout = "", stderr = "" }
	end
	return { code = 0, stdout = "", stderr = "" }
end

vim.system = function(command, opts, callback)
	system_calls[#system_calls + 1] = { command = command, opts = opts }
	local result = result_for(command)
	if type(callback) == "function" then
		callback(result)
	end
	return {
		wait = function()
			return result
		end,
	}
end

vim.ui.select = function(items, opts, on_choice)
	select_calls[#select_calls + 1] = {
		items = items,
		prompt = opts.prompt,
		labels = vim.tbl_map(opts.format_item, items),
		chunks = vim.tbl_map(function(item)
			return opts.format_item(item, true)
		end, items),
	}
	on_choice(items[1])
end

local snacks_select_calls = 0
local snacks_opts_calls = {}
package.loaded["snacks"] = {
	picker = {
		select = function(items, opts, on_choice)
			snacks_select_calls = snacks_select_calls + 1
			snacks_opts_calls[#snacks_opts_calls + 1] = opts
			vim.ui.select(items, opts, on_choice)
		end,
	},
}

local function same_pane(left, right)
	return left and right and left.pane_id == right.pane_id
end

local function choose(file_key, file_label, remembered_agent, agents, root, force_metadata_off)
	if remembered_agent then
		herdr._test.remember_agent(file_key, remembered_agent)
	end
	metadata_ok = not force_metadata_off
	live_agents = agents
	local metadata = herdr._test.load_metadata()
	local picked
	herdr._test.choose_agent(agents, file_key, file_label, root or "/tmp/herdr-test-no-match", metadata, function(agent)
		picked = agent
	end)
	return picked
end

assert(herdr._test.is_destination_agent(agent_a), "top-level supervisor must be a destination")
assert(herdr._test.is_destination_agent(agent_b), "second top-level supervisor must be a destination")
assert(not herdr._test.is_destination_agent(worker_a), "first supervisor worker must be excluded")
assert(not herdr._test.is_destination_agent(worker_b), "second supervisor worker must be excluded")

local loaded_state = assert(herdr._test.load_agent_state())
assert(#loaded_state.agents == 2, "agent state must retain only both top-level supervisors")
assert(same_pane(loaded_state.agents[1], agent_a), "first supervisor must remain addressable")
assert(same_pane(loaded_state.agents[2], agent_b), "second supervisor must remain addressable")

local label_a = herdr._test.agent_label(agent_a, herdr._test.load_metadata())
assert(label_a:find("Codex", 1, true), "agent type missing")
assert(label_a:find("session quick", 1, true), "session name missing")
assert(label_a:find("workspace dotfiles #3", 1, true), "workspace label/number missing")
assert(label_a:find("tab agents:t3 #3", 1, true), "tab label/number missing")
assert(label_a:find("@ main", 1, true), "branch missing")
assert(
	label_a:find("OC | Neovim leader h送信先ポップアップ改善と記憶機能", 1, true),
	"terminal title missing"
)
assert(label_a:find("pane w1S:p1", 1, true), "pane id missing")

local label_b = herdr._test.agent_label(agent_b, herdr._test.load_metadata())
assert(label_b:find("OpenCode", 1, true), "OpenCode label missing")
assert(label_b:find("workspace vpg-autoscaler #2", 1, true), "workspace metadata missing")
assert(label_b:find("tab agents:t1 #2", 1, true), "tab metadata missing")
assert(label_b:find("@ feature/autoscaler", 1, true), "feature branch missing")

local picked_a = choose(
	vim.fs.joinpath(dotfiles_root, "home/files/config/nvim/lua/config/alpha.lua"),
	"alpha.lua",
	agent_a,
	{ agent_a, worker_a, agent_b, worker_b }
)
assert(same_pane(picked_a, agent_a), "remembered file target must stay selected")
assert(#select_calls == 1, "chooser must be shown every time")
assert(select_calls[1].items[1].pane_id == agent_a.pane_id, "remembered agent must be first")
assert(#select_calls[1].items == 2, "workers from both supervisors must be absent from the chooser")
assert(select_calls[1].prompt:find("alpha.lua", 1, true), "chooser prompt must mention the file")
assert(select_calls[1].labels[1]:find("dotfiles #3 / agents:t3 #3", 1, true), "summary must stay compact")
assert(not select_calls[1].labels[1]:find("path ", 1, true), "summary must omit verbose path details")

local function has_chunk(chunks, text, highlight)
	return vim.iter(chunks):any(function(chunk)
		return chunk[1] == text and chunk[2] == highlight
	end)
end

local chunks = select_calls[1].chunks[1]
assert(has_chunk(chunks, "Codex", "HerdrAgent"), "agent accent missing")
assert(has_chunk(chunks, "working", "HerdrStatusWorking"), "status accent missing")
assert(has_chunk(chunks, "dotfiles #3 / agents:t3 #3", "HerdrWorkspace"), "workspace accent missing")
assert(has_chunk(chunks, "main", "HerdrBranch"), "branch accent missing")
assert(
	has_chunk(chunks, "OC | Neovim leader h送信先ポップアップ改善と記憶機能", "HerdrTitle"),
	"title accent missing"
)
assert(has_chunk(chunks, " · ", "HerdrSeparator"), "separator accent missing")
assert(vim.api.nvim_get_hl(0, { name = "HerdrWorkspace" }).fg == 0x94e2d5, "workspace must use Mocha teal")
assert(vim.api.nvim_get_hl(0, { name = "HerdrBranch" }).fg == 0xfab387, "branch must use Mocha peach")
assert(vim.tbl_contains(snacks_opts_calls[1].snacks.layout.hidden, "preview"), "details preview must stay hidden")
assert(snacks_opts_calls[1].snacks.preview == nil, "details preview must be removed")

local picked_b = choose(
	vim.fs.joinpath(dotfiles_root, "home/files/config/nvim/lua/config/beta.lua"),
	"beta.lua",
	agent_b,
	{ agent_a, worker_a, agent_b, worker_b }
)
assert(same_pane(picked_b, agent_b), "different files must remember independent targets")
assert(select_calls[2].items[1].pane_id == agent_b.pane_id, "the other file's target must be initially selected")

branch_by_cwd[dotfiles_root] = "feature/fresh"
local picked_a_again = choose(
	vim.fs.joinpath(dotfiles_root, "home/files/config/nvim/lua/config/alpha.lua"),
	"alpha.lua",
	agent_a,
	{ agent_a, worker_a, agent_b, worker_b }
)
assert(same_pane(picked_a_again, agent_a), "same target should still be selectable")
assert(select_calls[3].labels[1]:find("feature/fresh", 1, true), "branch cache must refresh per chooser")

local metadata_free_labels = choose(
	vim.fs.joinpath(dotfiles_root, "home/files/config/nvim/lua/config/fallback.lua"),
	"fallback.lua",
	nil,
	{ agent_a, worker_a, agent_b, worker_b },
	nil,
	true
)
assert(metadata_free_labels, "metadata failure must not break chooser")
local fallback_label = herdr._test.agent_label(agent_a, herdr._test.load_metadata())
assert(fallback_label:find("session default", 1, true), "metadata failure must fall back to session default")
assert(fallback_label:find("workspace w1", 1, true), "metadata failure must fall back to workspace ids")
assert(fallback_label:find("tab w1", 1, true), "metadata failure must fall back to tab ids")

local target = herdr._test.agent_signature(agent_a)
metadata_ok = true
live_agents = { agent_a, agent_b }
prompt_calls = {}
local sent = herdr._test.send_prompt(target, "hello world")
assert(sent, "live target must be sent")
assert(#prompt_calls == 1 and prompt_calls[1].pane_id == agent_a.pane_id, "prompt must go to the selected pane")

live_agents = { agent_a, worker_a, agent_b, worker_b }
local blocked_worker = herdr._test.send_prompt(herdr._test.agent_signature(worker_a), "must not reach worker")
assert(not blocked_worker, "worker must fail live destination validation")
assert(#prompt_calls == 1, "worker validation must not invoke herdr agent prompt")

vim.env.HERDR_SOCKET_PATH = default_socket
local blocked_herdr_session = herdr._test.send_prompt(target, "must not cross Herdr sessions")
assert(not blocked_herdr_session, "Herdr session change must fail closed")
assert(#prompt_calls == 1, "Herdr session change must not invoke herdr agent prompt")
vim.env.HERDR_SOCKET_PATH = quick_socket

live_agents = {
	{
		agent = "codex",
		agent_status = "working",
		cwd = dotfiles_root,
		focused = true,
		foreground_cwd = dotfiles_root,
		pane_id = "w1S:p1",
		tab_id = "w1S:t3",
		terminal_id = "term_a",
		terminal_title_stripped = "OC | changed session",
		workspace_id = "w1S",
		agent_session = { agent = "codex", kind = "id", source = "herdr:codex", value = "ses_new" },
	},
	agent_b,
}
local blocked_session = herdr._test.send_prompt(target, "should not send")
assert(not blocked_session, "session change must fail closed")
assert(#prompt_calls == 1, "session change must not invoke herdr agent prompt")

live_agents = {
	{
		agent = "codex",
		agent_status = "working",
		cwd = dotfiles_root,
		focused = true,
		foreground_cwd = dotfiles_root,
		pane_id = "w1S:p1",
		tab_id = "w1S:t3",
		terminal_id = "term_reused",
		terminal_title_stripped = "OC | reused pane",
		workspace_id = "w1S",
		agent_session = { agent = "codex", kind = "id", source = "herdr:codex", value = "ses_aaa" },
	},
	agent_b,
}
local blocked_reuse = herdr._test.send_prompt(target, "should also not send")
assert(not blocked_reuse, "pane reuse must fail closed")
assert(#prompt_calls == 1, "pane reuse must not invoke herdr agent prompt")

assert(
	vim.iter(notifications):any(function(item)
		return item.message:find("changed or disappeared", 1, true) ~= nil
	end),
	"blocked sends must explain that the selected agent changed"
)

live_agents = { agent_a, worker_a, agent_b, worker_b }
prompt_calls = {}
assert(herdr._test.send_prompt(herdr._test.agent_signature(agent_a), "to supervisor a"))
assert(herdr._test.send_prompt(herdr._test.agent_signature(agent_b), "to supervisor b"))
assert(not herdr._test.send_prompt(herdr._test.agent_signature(worker_a), "not to worker a"))
assert(not herdr._test.send_prompt(herdr._test.agent_signature(worker_b), "not to worker b"))
assert(#prompt_calls == 2, "only the two top-level supervisors may receive prompts")
assert(prompt_calls[1].pane_id == agent_a.pane_id, "first prompt must reach supervisor a")
assert(prompt_calls[2].pane_id == agent_b.pane_id, "second prompt must reach supervisor b")
assert(snacks_select_calls == #select_calls, "chooser must use Snacks so Enter confirms the initially selected target")
assert(#system_calls >= 10, "expected Herdr metadata and validation commands to run")

print("herdr agent selection regression: ok")
