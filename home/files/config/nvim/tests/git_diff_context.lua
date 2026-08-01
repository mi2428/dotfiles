local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
vim.opt.runtimepath:prepend(nvim_root)
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")

local original_cwd = vim.fn.getcwd()
local original_workspace_mode = vim.env.NVIM_WORKSPACE_MODE
local original_review_mode = vim.env.NVIM_REVIEW_MODE
local repo = vim.fn.tempname()
vim.fn.mkdir(repo, "p")

local function git(args)
	local command = { "git", "-C", repo }
	vim.list_extend(command, args)
	local result = vim.system(command, { text = true }):wait()
	assert(result.code == 0, vim.trim(result.stderr or result.stdout or "git command failed"))
	return vim.trim(result.stdout or "")
end

local function write(path, lines)
	assert(vim.fn.writefile(lines, vim.fs.joinpath(repo, path)) == 0)
end

local function load_context(workspace, review)
	vim.env.NVIM_WORKSPACE_MODE = workspace and "1" or nil
	vim.env.NVIM_REVIEW_MODE = review and "1" or nil
	package.loaded["config.git_diff_context"] = nil
	local module = require("config.git_diff_context")
	module.setup()
	return module
end

local ok, err = xpcall(function()
	git({ "init", "-q", "-b", "main" })
	git({ "config", "user.email", "diff-context@example.test" })
	git({ "config", "user.name", "Diff Context Test" })
	write("fixture.lua", { "return 'base'" })
	write("rename-source.lua", { "return 'renamed'" })
	git({ "add", "fixture.lua", "rename-source.lua" })
	git({ "commit", "-qm", "base" })
	local base_commit = git({ "rev-parse", "HEAD" })
	git({ "update-ref", "refs/remotes/origin/main", "HEAD" })
	git({ "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main" })
	git({ "switch", "-qc", "feature" })
	write("fixture.lua", { "return 'feature'" })
	write("added.lua", { "return 'added'" })
	git({ "mv", "rename-source.lua", "renamed.lua" })
	git({ "add", "fixture.lua", "added.lua" })
	git({ "commit", "-qm", "feature" })
	vim.cmd.cd(vim.fn.fnameescape(repo))
	local buf = vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_set_name(buf, vim.fs.joinpath(repo, "fixture.lua"))

	local ordinary = load_context(false, false)
	assert(ordinary.current() == "uncommitted")
	assert(ordinary.resolve_base(buf) == "HEAD", "ordinary Neovim must compare all uncommitted changes against HEAD")

	local branch = load_context(true, false)
	assert(branch.current() == "branch")
	assert(branch.resolve_base(buf) == base_commit, "bin/work must compare against the branch merge-base")
	assert(
		branch.added_file_revision(buf, base_commit) == nil,
		"modified branch files must retain Gitsigns rename handling"
	)
	local added_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(added_buf, vim.fs.joinpath(repo, "added.lua"))
	local added_revision = assert(branch.added_file_revision(added_buf, base_commit))
	assert(added_revision.base == base_commit and added_revision.relpath == "added.lua")
	local renamed_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(renamed_buf, vim.fs.joinpath(repo, "renamed.lua"))
	assert(branch.added_file_revision(renamed_buf, base_commit) == nil, "renamed files must retain their base blob")

	write("untracked.lua", { "return 'untracked'" })
	local untracked_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(untracked_buf, vim.fs.joinpath(repo, "untracked.lua"))
	local untracked_revision = assert(ordinary.added_file_revision(untracked_buf, "HEAD"))
	assert(untracked_revision.base == "HEAD" and untracked_revision.relpath == "untracked.lua")

	package.loaded["config.review"] = {
		gitsigns_base = function()
			return "review-merge-base"
		end,
	}
	local review = load_context(false, true)
	assert(review.current() == "review")
	assert(review.resolve_base(buf) == "review-merge-base", "gh-review must use the PR merge-base")
end, debug.traceback)

vim.cmd.cd(vim.fn.fnameescape(original_cwd))
vim.env.NVIM_WORKSPACE_MODE = original_workspace_mode
vim.env.NVIM_REVIEW_MODE = original_review_mode
vim.fn.delete(repo, "rf")
assert(ok, err)

print("Git diff context regression: ok")
