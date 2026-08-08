local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_config = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
package.path = table.concat({
	vim.fs.joinpath(nvim_config, "lua/?.lua"),
	vim.fs.joinpath(nvim_config, "lua/?/init.lua"),
	package.path,
}, ";")

local workspace_config = require("config.obsidian")
local specs = dofile(vim.fs.joinpath(nvim_config, "lua/plugins/editing.lua"))
local obsidian
for _, spec in ipairs(specs) do
	if spec[1] == "obsidian-nvim/obsidian.nvim" then
		obsidian = spec
		break
	end
end

assert(obsidian, "obsidian.nvim plugin spec is missing")
assert(obsidian.version == "*", "obsidian.nvim must follow a stable release")
assert(vim.deep_equal(obsidian.ft, { "markdown" }), "obsidian.nvim must load only for Markdown")
assert(type(obsidian.opts) == "function", "obsidian.nvim options must resolve against the current Markdown buffer")
assert(type(obsidian.config) == "function", "obsidian.nvim must install dynamic workspace handling")

local function realpath(path)
	return assert(vim.uv.fs_realpath(path), "path must exist: " .. path)
end

local temp_dir = vim.fn.tempname()
local vault = vim.fs.joinpath(temp_dir, "vault")
local nested = vim.fs.joinpath(vault, "notes", "nested")
local loose = vim.fs.joinpath(temp_dir, "loose")
local project = vim.fs.joinpath(temp_dir, "project")
local project_docs = vim.fs.joinpath(project, "docs")
vim.fn.mkdir(vim.fs.joinpath(vault, ".obsidian"), "p")
vim.fn.mkdir(nested, "p")
vim.fn.mkdir(loose, "p")
vim.fn.mkdir(vim.fs.joinpath(project, ".git"), "p")
vim.fn.mkdir(project_docs, "p")

local original_buf = vim.api.nvim_get_current_buf()
local original_obsidian = _G.Obsidian
local original_workspace_module = package.loaded["obsidian.workspace"]
local buf = vim.api.nvim_create_buf(false, true)
local ok, err = xpcall(function()
	vim.api.nvim_set_current_buf(buf)
	vim.api.nvim_buf_set_name(buf, vim.fs.joinpath(nested, "note.md"))
	local opts = obsidian.opts()
	assert(opts.legacy_commands == false, "obsidian.nvim legacy commands must stay disabled")
	assert(opts.ui.enable == false, "render-markdown owns Markdown UI, so Obsidian UI must stay disabled")
	local workspace = assert(opts.workspaces[1], "initial Markdown workspace is missing")
	assert(realpath(workspace.path) == realpath(vault), "initial workspace must discover the nearest vault")
	assert(workspace.overrides.new_notes_location == "current_dir", "new notes must stay beside the current note")
	assert(workspace.overrides.frontmatter.enabled == false, "ordinary Markdown saves must not inject frontmatter")
	assert(workspace.overrides.footer.enabled == false, "obsidian.nvim footer work must stay disabled")
	assert(workspace.overrides.notes_subdir == vim.NIL, "dynamic workspaces must not create a notes directory")
	assert(workspace.overrides.templates.folder == vim.NIL, "dynamic workspaces must not create templates")

	vim.api.nvim_buf_set_name(buf, vim.fs.joinpath(loose, "note.md"))
	assert(realpath(workspace_config.workspace_root(buf)) == realpath(loose), "loose notes must use their parent")
	vim.api.nvim_buf_set_name(buf, vim.fs.joinpath(project_docs, "note.md"))
	assert(realpath(workspace_config.workspace_root(buf)) == realpath(project), "project notes must use their git root")

	local initial = {
		name = "markdown:vault",
		path = realpath(vault),
		root = realpath(vault),
		overrides = workspace.overrides,
	}
	_G.Obsidian = { workspaces = { initial }, workspace = initial }
	local set_calls = 0
	package.loaded["obsidian.workspace"] = {
		new = function(spec)
			local path = realpath(spec.path)
			return { name = spec.name, path = path, root = path, overrides = spec.overrides }
		end,
		set = function(next_workspace)
			set_calls = set_calls + 1
			Obsidian.workspace = next_workspace
		end,
	}

	vim.api.nvim_buf_set_name(buf, vim.fs.joinpath(loose, "note.md"))
	local loose_workspace, added, changed = workspace_config.ensure_workspace(buf)
	assert(loose_workspace and added and changed, "a note outside known workspaces must add and select one")
	assert(#Obsidian.workspaces == 2, "dynamic workspace must be retained for later buffer switches")
	assert(realpath(loose_workspace.path) == realpath(loose), "dynamic workspace must use the loose note parent")

	table.insert(Obsidian.workspaces, 1, {
		name = "markdown:parent",
		path = realpath(temp_dir),
		root = realpath(temp_dir),
		overrides = workspace.overrides,
	})
	vim.api.nvim_buf_set_name(buf, vim.fs.joinpath(nested, "note.md"))
	local vault_workspace, vault_added, vault_changed = workspace_config.ensure_workspace(buf)
	assert(vault_workspace == initial, "returning to a known vault must reuse its workspace")
	assert(not vault_added and vault_changed, "known vault switches must not duplicate workspaces")
	assert(Obsidian.workspaces[1] == initial, "selected nested workspaces must take precedence over parent roots")
	assert(set_calls == 2, "workspace changes must update obsidian.nvim state")
end, debug.traceback)

package.loaded["obsidian.workspace"] = original_workspace_module
_G.Obsidian = original_obsidian
vim.api.nvim_set_current_buf(original_buf)
vim.api.nvim_buf_delete(buf, { force = true })
vim.fn.delete(temp_dir, "rf")
assert(ok, err)
print("obsidian workspace: ok")
