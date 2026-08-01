local M = {}

local context = "uncommitted"

local function git(args, cwd)
	local command = { "git", "-C", cwd }
	vim.list_extend(command, args)
	local result = vim.system(command, { text = true }):wait()
	if result.code ~= 0 then
		return nil, vim.trim(result.stderr or result.stdout or "")
	end
	return vim.trim(result.stdout or ""), nil
end

local function repository_root(buf)
	local name = vim.api.nvim_buf_get_name(buf)
	local cwd = name ~= "" and vim.fs.dirname(name) or vim.fn.getcwd()
	return git({ "rev-parse", "--show-toplevel" }, cwd)
end

local function repository_file(buf)
	local name = vim.api.nvim_buf_get_name(buf)
	if name == "" then
		return nil
	end
	local root = repository_root(buf)
	if not root or not vim.startswith(name, root .. "/") then
		return nil
	end
	return root, name:sub(#root + 2)
end

local function origin_default_branch(root)
	local symbolic = git({ "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD" }, root)
	if symbolic and symbolic ~= "" then
		return symbolic
	end

	for _, candidate in ipairs({ "origin/main", "origin/master" }) do
		local resolved = git({ "rev-parse", "--verify", "--quiet", candidate .. "^{commit}" }, root)
		if resolved and resolved ~= "" then
			return candidate
		end
	end

	return nil, "origin's default branch is unavailable (tried origin/HEAD, origin/main, origin/master)"
end

local function branch_merge_base(buf)
	local root, root_error = repository_root(buf)
	if not root or root == "" then
		return nil, root_error ~= "" and root_error or "the current buffer is not inside a Git worktree"
	end

	local base, base_error = origin_default_branch(root)
	if not base then
		return nil, base_error
	end

	local merge_base, merge_error = git({ "merge-base", base, "HEAD" }, root)
	if not merge_base or merge_base == "" then
		return nil, merge_error ~= "" and merge_error or ("no merge-base exists between %s and HEAD"):format(base)
	end
	return merge_base
end

function M.setup()
	if vim.env.NVIM_REVIEW_MODE == "1" then
		context = "review"
	elseif vim.env.NVIM_WORKSPACE_MODE == "1" then
		context = "branch"
	else
		context = "uncommitted"
	end
end

function M.current()
	return context
end

function M.resolve_base(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	if context == "review" then
		local base = require("config.review").gitsigns_base()
		if base and base ~= "" then
			return base
		end
		return nil, "the review merge-base is unavailable"
	end
	if context == "branch" then
		return branch_merge_base(buf)
	end
	return "HEAD"
end

-- Gitsigns can follow renames, but it cannot create a revision buffer when the
-- selected base has no blob at all. Identify only genuinely added/untracked
-- files so Git diff peek can provide an empty left-hand revision for them.
function M.added_file_revision(buf, base)
	local root, relpath = repository_file(buf)
	if not root then
		return nil
	end

	local object = git({ "cat-file", "-e", base .. ":" .. relpath }, root)
	if object ~= nil then
		return nil
	end

	local changes = git({ "diff", "--name-status", "-z", "--find-renames", base, "--" }, root)
	local fields = changes and vim.split(changes, "\0", { plain = true, trimempty = true }) or {}
	local added = false
	local index = 1
	while index <= #fields do
		local status = fields[index]
		local renamed = status:match("^[RC]") ~= nil
		local path = fields[index + (renamed and 2 or 1)]
		if path == relpath then
			added = status == "A"
			break
		end
		index = index + (renamed and 3 or 2)
	end
	if not added then
		local untracked = git({ "ls-files", "--others", "--exclude-standard", "--", relpath }, root)
		added = untracked ~= nil and untracked ~= ""
	end
	if not added then
		return nil
	end

	local git_dir = git({ "rev-parse", "--path-format=absolute", "--git-dir" }, root)
	if not git_dir or git_dir == "" then
		return nil
	end
	return {
		base = base,
		git_dir = git_dir,
		relpath = relpath,
	}
end

return M
