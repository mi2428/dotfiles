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

local function run(command)
	local result = vim.system(command, { text = true }):wait()
	if result.code ~= 0 then
		error(("command failed (%d): %s\n%s"):format(result.code, table.concat(command, " "), result.stderr or ""))
	end
end

local function visible_paths()
	local paths = {}
	for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		local path = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(winid))
		if path ~= "" then
			paths[vim.uv.fs_realpath(path) or vim.fs.normalize(path)] = true
		end
	end
	return paths
end

local root = vim.fn.tempname()
local first = vim.fs.joinpath(root, "01-first.txt")
local second = vim.fs.joinpath(root, "02-second.txt")
local third = vim.fs.joinpath(root, "03-third.txt")
vim.fn.mkdir(root, "p")
vim.fn.writefile({ "first" }, first)
vim.fn.writefile({ "second" }, second)
vim.fn.writefile({ "third" }, third)
run({ "git", "init", "-q", root })
run({ "git", "-C", root, "add", "." })
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
vim.fn.writefile({ "FIRST" }, first)

vim.env.CODEX_NVIM_EDIT_EVENT_DIR = root .. "-events"
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
		return vim.fn.bufnr(first) > 0 and visible_paths()[vim.uv.fs_realpath(first)]
	end, 20),
	"the first watched file was not opened"
)
assert_equal(#vim.api.nvim_tabpage_list_wins(0), 1, "one watched file must use one window")

vim.fn.writefile({ "SECOND" }, second)
assert(
	vim.wait(3000, function()
		return vim.fn.bufnr(second) > 0 and #vim.api.nvim_tabpage_list_wins(0) == 2
	end, 20),
	"the second watched file was not opened in a vertical split"
)
local visible = visible_paths()
assert(visible[vim.uv.fs_realpath(first)], "the first watched file must remain visible")
assert(visible[vim.uv.fs_realpath(second)], "the second watched file must be visible beside it")
local windows = vim.api.nvim_tabpage_list_wins(0)
local first_position = vim.api.nvim_win_get_position(windows[1])
local second_position = vim.api.nvim_win_get_position(windows[2])
assert_equal(first_position[1], second_position[1], "watched files must share the same screen row")
assert(first_position[2] ~= second_position[2], "watched files must be arranged in vertical splits")
assert_equal(
	vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf()),
	vim.uv.fs_realpath(second),
	"follow must focus the second edited file"
)

vim.fn.writefile({ "THIRD" }, third)
assert(
	vim.wait(3000, function()
		return vim.fn.bufnr(third) > 0 and visible_paths()[vim.uv.fs_realpath(third)]
	end, 20),
	"follow did not reuse an existing split for the third watched file"
)
assert_equal(#vim.api.nvim_tabpage_list_wins(0), 2, "additional watched files must not create more splits")
visible = visible_paths()
assert(visible[vim.uv.fs_realpath(third)], "the latest edited file must be visible")
assert(
	visible[vim.uv.fs_realpath(first)] or visible[vim.uv.fs_realpath(second)],
	"one previously watched file must remain visible beside the latest edit"
)
assert_equal(
	vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf()),
	vim.uv.fs_realpath(third),
	"follow must focus the latest edited file"
)

vim.fn.writefile({ "first" }, first)
vim.fn.writefile({ "second" }, second)
assert(
	vim.wait(3000, function()
		return #vim.api.nvim_tabpage_list_wins(0) == 1 and visible_paths()[vim.uv.fs_realpath(third)]
	end, 20),
	"clean watched files must collapse the layout back to one window"
)

vim.fn.writefile({ "SECOND AGAIN" }, second)
assert(
	vim.wait(3000, function()
		local current_visible = visible_paths()
		return #vim.api.nvim_tabpage_list_wins(0) == 2
			and current_visible[vim.uv.fs_realpath(second)]
			and current_visible[vim.uv.fs_realpath(third)]
	end, 20),
	"a later second watched file must recreate the vertical split"
)
windows = vim.api.nvim_tabpage_list_wins(0)
first_position = vim.api.nvim_win_get_position(windows[1])
second_position = vim.api.nvim_win_get_position(windows[2])
assert_equal(first_position[1], second_position[1], "recreated watched windows must share the same screen row")
assert(first_position[2] ~= second_position[2], "the recreated layout must still use vertical splits")

watcher.stop({ notify = false })
vim.fn.delete(root, "rf")
vim.fn.delete(root .. "-events", "rf")
print("diff_watch split layout: ok")
