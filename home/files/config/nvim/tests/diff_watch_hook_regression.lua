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
local event_dir = root .. "-events"
local source = vim.fs.joinpath(root, "follow.txt")
vim.fn.mkdir(root, "p")
vim.fn.writefile({ "one", "two", "three", "four", "five", "six" }, source)
run({ "git", "init", "-q", root })
run({ "git", "-C", root, "add", "follow.txt" })
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
vim.fn.writefile({ "one", "two before watch", "three", "four", "five", "six" }, source)

vim.env.CODEX_NVIM_EDIT_EVENT_DIR = event_dir
vim.env.NVIM_DIFF_WATCH_BASE = "worktree"
vim.env.NVIM_DIFF_WATCH_DIR = root
vim.env.NVIM_DIFF_WATCH_FOLLOW = "1"
vim.env.NVIM_DIFF_WATCH_INTERVAL_MS = "100"
vim.env.NVIM_DIFF_WATCH_MODE = "1"
vim.env.NVIM_DIFF_WATCH_ROOT = root

local watcher = require("config.diff_watch")
watcher.setup()
vim.api.nvim_exec_autocmds("VimEnter", { modeline = false })
assert(
	vim.wait(3000, function()
		local bufnr = vim.fn.bufnr(source)
		return bufnr > 0 and vim.api.nvim_buf_is_loaded(bufnr)
	end, 20),
	"the original Git watcher must still open an existing changed file"
)

local bufnr = vim.fn.bufnr(source)
vim.api.nvim_set_current_buf(bufnr)
vim.api.nvim_win_set_cursor(0, { 1, 0 })

local patch = table.concat({
	"*** Begin Patch",
	"*** Update File: follow.txt",
	"@@",
	"-two before watch",
	"+TWO FROM CODEX",
	"@@",
	"-five",
	"+FIVE FROM CODEX",
	"*** End Patch",
}, "\n")
local common = {
	cwd = root,
	model = "codex-test",
	permission_mode = "default",
	session_id = "session-regression",
	turn_id = "turn-regression",
	tool_input = { command = patch },
	tool_name = "apply_patch",
	tool_use_id = "tool-regression",
}
local hook = vim.fs.joinpath(dotfiles_root, "home/files/libexec/dotfiles/codex-nvim-edit-event")
run({ hook, "pre" }, {
	stdin = vim.json.encode(vim.tbl_extend("force", common, { hook_event_name = "PreToolUse" })),
	text = true,
})

-- Headless Neovim cannot remain in Insert mode without an attached UI. A
-- modified buffer exercises the same can_follow_now() deferral branch; the
-- mode-specific branch is the preceding explicit mode == "n" guard.
vim.bo[bufnr].modified = true
vim.fn.writefile({ "one", "TWO FROM CODEX", "three", "four", "FIVE FROM CODEX", "six" }, source)
run({ hook, "post" }, {
	stdin = vim.json.encode(vim.tbl_extend("force", common, {
		hook_event_name = "PostToolUse",
		tool_response = "Success. Updated files.",
		tool_use_id = "tool-regression",
	})),
	text = true,
})

assert(
	vim.wait(2000, function()
		return watcher.codex_status() ~= nil
	end, 20),
	"the Git watcher did not consume the Codex hook event"
)
assert_equal(vim.api.nvim_win_get_cursor(0)[1], 1, "an unsafe editor state must defer automatic follow")

vim.bo[bufnr].modified = false
vim.api.nvim_buf_call(bufnr, function()
	vim.cmd("silent checktime")
end)
vim.api.nvim_exec_autocmds("ModeChanged", { modeline = false })
assert(
	vim.wait(2000, function()
		return vim.api.nvim_win_get_cursor(0)[1] == 5
	end, 20),
	"returning to a safe editor state must flush the queued final-hunk follow"
)

assert_equal(vim.api.nvim_buf_get_lines(bufnr, 1, 2, false)[1], "TWO FROM CODEX", "autoread must reload Codex changes")
watcher.stop({ notify = false })
vim.fn.delete(root, "rf")
vim.fn.delete(event_dir, "rf")
print("diff_watch hook regression: ok")
