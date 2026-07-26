local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
vim.opt.runtimepath:prepend(vim.fs.joinpath(dotfiles_root, "home/files/config/nvim"))
package.path = table.concat({
	vim.fs.joinpath(dotfiles_root, "home/files/config/nvim/lua/?.lua"),
	vim.fs.joinpath(dotfiles_root, "home/files/config/nvim/lua/?/init.lua"),
	package.path,
}, ";")

local function assert_equal(actual, expected, message)
	if not vim.deep_equal(actual, expected) then
		error(("%s\nexpected: %s\nactual:   %s"):format(message, vim.inspect(expected), vim.inspect(actual)))
	end
end

local function run(command, options)
	local result = vim.system(command, options or { text = true }):wait()
	if result.code ~= 0 then
		error(("command failed (%d): %s\n%s"):format(result.code, table.concat(command, " "), result.stderr or ""))
	end
	return result
end

local root = vim.fn.tempname()
local event_dir = vim.fs.joinpath(root, "events")
local source = vim.fs.joinpath(root, "alpha.txt")
vim.fn.mkdir(root, "p")
vim.fn.writefile({ "one", "two", "three", "four", "five", "six" }, source)
run({ "git", "init", "-q", root })
run({ "git", "-C", root, "add", "alpha.txt" })
run({
	"git",
	"-C",
	root,
	"-c",
	"user.name=Codex Test",
	"-c",
	"user.email=codex-test@example.invalid",
	"commit",
	"-qm",
	"initial",
})

vim.env.CODEX_NVIM_EDIT_EVENT_DIR = event_dir
local hook = vim.env.CODEX_NVIM_EDIT_HOOK
	or vim.fs.joinpath(dotfiles_root, "home/files/libexec/dotfiles/codex-nvim-edit-event")
local watcher = require("config.codex_edit_watch")
local followed = {}
local refresh_count = 0
watcher.setup({
	history_limit = 4,
	repo_root = root,
	scope_dir = root,
	refresh = function()
		refresh_count = refresh_count + 1
	end,
	follow = function(candidate)
		followed[#followed + 1] = candidate
		if candidate.on_follow then
			candidate.on_follow()
		end
	end,
})

local patch = table.concat({
	"*** Begin Patch",
	"*** Update File: alpha.txt",
	"@@",
	"-two",
	"+TWO",
	"@@",
	"-five",
	"+FIVE",
	"*** End Patch",
}, "\n")
local common = {
	cwd = root,
	model = "codex-test",
	permission_mode = "default",
	session_id = "session-12345678",
	turn_id = "turn-abcdefgh",
	tool_input = { command = patch },
	tool_name = "apply_patch",
}

local pre = vim.tbl_extend("force", common, { hook_event_name = "PreToolUse", tool_use_id = "tool-1" })
run({ hook, "pre" }, { stdin = vim.json.encode(pre), text = true })
vim.fn.writefile({ "one", "TWO", "three", "four", "FIVE", "six" }, source)
local post = vim.tbl_extend("force", common, {
	hook_event_name = "PostToolUse",
	tool_response = "Success. Updated files.",
	tool_use_id = "tool-1",
})
run({ hook, "post" }, { stdin = vim.json.encode(post), text = true })

local second_patch = table.concat({
	"*** Begin Patch",
	"*** Update File: alpha.txt",
	"@@",
	"-six",
	"+SIX",
	"*** End Patch",
}, "\n")
local second_common = vim.tbl_extend("force", common, {
	tool_input = { command = second_patch },
	tool_use_id = "tool-2",
})
run({ hook, "pre" }, {
	stdin = vim.json.encode(vim.tbl_extend("force", second_common, { hook_event_name = "PreToolUse" })),
	text = true,
})
vim.fn.writefile({ "one", "TWO", "three", "four", "FIVE", "SIX" }, source)
run({ hook, "post" }, {
	stdin = vim.json.encode(vim.tbl_extend("force", second_common, {
		hook_event_name = "PostToolUse",
		tool_response = "Success. Updated files.",
		tool_use_id = "tool-2",
	})),
	text = true,
})

assert(
	vim.wait(2000, function()
		local status = watcher.status()
		return status ~= nil and #followed == 1
	end, 20),
	"timed out waiting for the PostToolUse event"
)
assert_equal(followed[1].line, 6, "same-turn patch events must coalesce onto the final hunk")
assert_equal(refresh_count, 2, "each patch event must request immediate Git reconciliation")

local status = assert(watcher.status(), "Codex status must be available after an edit")
assert_equal(status.active, true, "the turn must remain active until Stop")
assert_equal(status.line, 6, "statusline must point at the latest hunk")

local bufnr = vim.fn.bufnr(source)
assert(bufnr > 0, "the edited file must be loaded")
local namespaces = vim.api.nvim_get_namespaces()
local marker_namespace = assert(namespaces["dotfiles-codex-edit-markers"], "Codex marker namespace must exist")
local sign_namespace = assert(namespaces["dotfiles-codex-edit-signs"], "Codex sign namespace must exist")

local function codex_indicator_lines(buffer)
	local lines = {}
	for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buffer, sign_namespace, 0, -1, { details = true })) do
		assert_equal(vim.trim(mark[4].sign_text or ""), "", "the Codex indicator must use stable metadata")
		lines[#lines + 1] = mark[2] + 1
	end
	return lines
end

assert_equal(codex_indicator_lines(bufnr), { 6 }, "only the latest Codex hunk may expose an AI indicator")
local history_marks = vim.api.nvim_buf_get_extmarks(bufnr, marker_namespace, 0, -1, { details = true })
assert_equal(#history_marks, 3, "every changed hunk must retain a history marker")
for _, mark in ipairs(history_marks) do
	assert(mark[4].sign_text == nil, "history markers must never render signs")
end

watcher.previous_edit()
assert_equal(vim.api.nvim_win_get_cursor(0)[1], 5, "[a must move to the previous Codex hunk")
watcher.previous_edit()
assert_equal(vim.api.nvim_win_get_cursor(0)[1], 2, "repeated [a must continue through Codex history")
watcher.next_edit()
assert_equal(vim.api.nvim_win_get_cursor(0)[1], 5, "]a must move to the next Codex hunk")
watcher.next_edit()
assert_equal(vim.api.nvim_win_get_cursor(0)[1], 6, "repeated ]a must reach the latest Codex hunk")

watcher.open_quickfix()
local quickfix = vim.fn.getqflist({ items = 1, title = 1 })
assert_equal(#quickfix.items, 3, "turn quickfix must contain every hunk")
assert(quickfix.title:find("turn%-abc", 1) ~= nil, "turn quickfix title must identify the turn")
vim.cmd("cclose")

-- Identical patch commands still need independent snapshots. Run their Post
-- hooks in reverse order to expose collisions between tool invocations.
local repeated_patch = table.concat({
	"*** Begin Patch",
	"*** Update File: alpha.txt",
	"@@",
	"-SIX",
	"+SIX AGAIN",
	"*** End Patch",
}, "\n")
local repeated_common = vim.tbl_extend("force", common, { tool_input = { command = repeated_patch } })
local repeated_a = vim.tbl_extend("force", repeated_common, { tool_use_id = "tool-repeated-a" })
local repeated_b = vim.tbl_extend("force", repeated_common, { tool_use_id = "tool-repeated-b" })
run({ hook, "pre" }, {
	stdin = vim.json.encode(vim.tbl_extend("force", repeated_a, { hook_event_name = "PreToolUse" })),
	text = true,
})
vim.fn.writefile({ "one", "TWO", "three", "four", "FIVE", "SIX A" }, source)
run({ hook, "pre" }, {
	stdin = vim.json.encode(vim.tbl_extend("force", repeated_b, { hook_event_name = "PreToolUse" })),
	text = true,
})
vim.fn.writefile({ "one", "TWO", "three", "four", "FIVE", "SIX B" }, source)
for _, payload in ipairs({ repeated_b, repeated_a }) do
	run({ hook, "post" }, {
		stdin = vim.json.encode(vim.tbl_extend("force", payload, { hook_event_name = "PostToolUse" })),
		text = true,
	})
end
assert(
	vim.wait(2000, function()
		return refresh_count >= 4
	end, 20),
	"identical patch commands must retain independent snapshots"
)

assert_equal(watcher._test.history_size(), 4, "Codex history must respect its configured limit")
assert_equal(codex_indicator_lines(bufnr), { 6 }, "repeated edits must move one AI indicator")
watcher.open_quickfix()
quickfix = vim.fn.getqflist({ items = 1, title = 1 })
assert_equal(#quickfix.items, 4, "history trimming must also prune turn quickfix entries")
vim.cmd("cclose")

local bash_common = vim.tbl_extend("force", common, {
	tool_input = { command = "formatter alpha.txt" },
	tool_name = "Bash",
	tool_use_id = "tool-bash",
})
run({ hook, "pre" }, {
	stdin = vim.json.encode(vim.tbl_extend("force", bash_common, { hook_event_name = "PreToolUse" })),
	text = true,
})
vim.fn.writefile({ "one", "TWO", "THREE", "four", "FIVE", "SIX B" }, source)
run({ hook, "post" }, {
	stdin = vim.json.encode(vim.tbl_extend("force", bash_common, {
		hook_event_name = "PostToolUse",
		tool_response = "Command completed.",
	})),
	text = true,
})
assert(
	vim.wait(2000, function()
		local current = watcher.status()
		return current ~= nil and current.line == 3 and refresh_count >= 5
	end, 20),
	"Bash PostToolUse must identify and follow the exact changed hunk"
)
assert_equal(codex_indicator_lines(bufnr), { 3 }, "Bash edits must move the sole Codex indicator")

local refresh = vim.tbl_extend("force", common, {
	hook_event_name = "PostToolUse",
	tool_name = "Bash",
})
run({ hook, "refresh" }, { stdin = vim.json.encode(refresh), text = true })
assert(
	vim.wait(2000, function()
		return refresh_count >= 6
	end, 20),
	"Bash PostToolUse must trigger immediate reconciliation"
)

local second_source = vim.fs.joinpath(root, "beta.txt")
vim.fn.writefile({ "before" }, second_source)
local second_file_patch = table.concat({
	"*** Begin Patch",
	"*** Update File: beta.txt",
	"@@",
	"-before",
	"+after",
	"*** End Patch",
}, "\n")
local second_file_common = vim.tbl_extend("force", common, {
	tool_input = { command = second_file_patch },
	tool_use_id = "tool-second-file",
	turn_id = "turn-second-file",
})
run({ hook, "pre" }, {
	stdin = vim.json.encode(vim.tbl_extend("force", second_file_common, { hook_event_name = "PreToolUse" })),
	text = true,
})
vim.fn.writefile({ "after" }, second_source)
run({ hook, "post" }, {
	stdin = vim.json.encode(vim.tbl_extend("force", second_file_common, {
		hook_event_name = "PostToolUse",
		tool_response = "Success. Updated files.",
	})),
	text = true,
})
assert(
	vim.wait(2000, function()
		local current = watcher.status()
		return current ~= nil and current.path:find("beta.txt", 1, true) ~= nil and refresh_count >= 7
	end, 20),
	"a later edit in another buffer must become the visible Codex target"
)
local second_bufnr = vim.fn.bufnr(second_source)
assert(second_bufnr > 0, "the second edited file must be loaded")
assert_equal(codex_indicator_lines(bufnr), {}, "moving the AI indicator must clear the previous buffer")
assert_equal(codex_indicator_lines(second_bufnr), { 1 }, "only the newest buffer may expose the AI indicator")

local stop = vim.tbl_extend("force", second_file_common, { hook_event_name = "Stop" })
run({ hook, "stop" }, { stdin = vim.json.encode(stop), text = true })
assert(
	vim.wait(2000, function()
		local current = watcher.status()
		return current and current.active == false and refresh_count >= 8
	end, 20),
	"Stop must close the active turn and reconcile once more"
)

watcher.open_quickfix({ session = true })
quickfix = vim.fn.getqflist({ items = 1, title = 1 })
assert_equal(#quickfix.items, 4, "session quickfix must honor the bounded edit history")
assert(quickfix.title:find("session%-", 1) ~= nil, "session quickfix title must identify the session")
vim.cmd("cclose")

watcher.stop()
vim.fn.delete(root, "rf")
print("codex_edit_watch integration: ok")
