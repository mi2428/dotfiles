local M = {}

local workspace_overrides = {
	frontmatter = {
		enabled = false,
	},
	footer = {
		enabled = false,
	},
	new_notes_location = "current_dir",
	notes_subdir = vim.NIL,
	templates = {
		folder = vim.NIL,
	},
}

local function buffer_directory(bufnr)
	local path = vim.api.nvim_buf_get_name(bufnr or 0)
	return vim.fs.normalize(path ~= "" and vim.fs.dirname(path) or vim.fn.getcwd())
end

local function canonical(path)
	return vim.uv.fs_realpath(path) or vim.fs.normalize(path)
end

function M.workspace_root(bufnr)
	local directory = buffer_directory(bufnr)
	local obsidian_marker = vim.fs.find(".obsidian", {
		path = directory,
		upward = true,
		type = "directory",
	})[1]
	if obsidian_marker then
		return canonical(vim.fs.dirname(obsidian_marker))
	end

	local git_marker = vim.fs.find(".git", {
		path = directory,
		upward = true,
	})[1]
	return canonical(git_marker and vim.fs.dirname(git_marker) or directory)
end

function M.workspace_spec(bufnr)
	local root = M.workspace_root(bufnr)
	return {
		name = "markdown:" .. root,
		path = root,
		overrides = vim.deepcopy(workspace_overrides),
	}
end

local function find_exact_workspace(root)
	for _, workspace in ipairs(Obsidian.workspaces or {}) do
		if canonical(tostring(workspace.path)) == root then
			return workspace
		end
	end
end

local function prioritize_workspace(workspace)
	for index, candidate in ipairs(Obsidian.workspaces) do
		if candidate == workspace then
			if index > 1 then
				table.remove(Obsidian.workspaces, index)
				table.insert(Obsidian.workspaces, 1, workspace)
			end
			return
		end
	end
end

function M.ensure_workspace(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not _G.Obsidian or not vim.api.nvim_buf_is_valid(bufnr) then
		return nil, false, false
	end

	local root = M.workspace_root(bufnr)
	local workspace = find_exact_workspace(root)
	local added = false
	if not workspace then
		workspace = require("obsidian.workspace").new(M.workspace_spec(bufnr))
		if not workspace then
			return nil, false, false
		end
		table.insert(Obsidian.workspaces, 1, workspace)
		added = true
	end
	prioritize_workspace(workspace)

	local changed = Obsidian.workspace ~= workspace
	if changed then
		require("obsidian.workspace").set(workspace)
	end
	return workspace, added, changed
end

function M.setup(opts)
	require("obsidian").setup(opts)

	local group = vim.api.nvim_create_augroup("dotfiles-obsidian-workspaces", { clear = true })
	vim.api.nvim_create_autocmd({ "BufReadPre", "BufNewFile", "BufEnter" }, {
		group = group,
		pattern = { "*.md", "*.markdown" },
		callback = function(args)
			M.ensure_workspace(args.buf)
		end,
	})
	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		pattern = "markdown",
		callback = function(args)
			M.ensure_workspace(args.buf)
		end,
	})
end

return M
