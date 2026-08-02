local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
local source = vim.fs.joinpath(nvim_root, "lua/plugins/lsp.lua")

vim.o.columns = 200
vim.o.lines = 70

local function normalize(path)
	return vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
end

local function roles()
	local worktree, revision = 0, 0
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		local role = vim.w[win].dotfiles_git_diff_peek_role
		if role == "worktree" then
			worktree = worktree + 1
		elseif role == "revision" then
			revision = revision + 1
		end
	end
	return worktree, revision
end

local function wait_for(label, predicate, timeout)
	assert(vim.wait(timeout or 10000, predicate, 25), label)
end

local function press(keys)
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "x", false)
end

local function popup_state(label)
	local worktree, revision = roles()
	assert(worktree == 1 and revision == 1, label .. ": popup panes must remain open")
	assert(vim.t.diffview_view_initialized ~= true, label .. ": popup must not become Diffview")
end

local function popup_win(role)
	return vim.iter(vim.api.nvim_tabpage_list_wins(0)):find(function(win)
		return vim.w[win].dotfiles_git_diff_peek_role == role
	end)
end

local function wait_for_preview(source_win, expected_path, expected_line, expected_col, label)
	wait_for(label .. ": Glance preview did not focus the definition", function()
		local win = vim.api.nvim_get_current_win()
		if win == source_win or not vim.api.nvim_win_is_valid(win) then
			return false
		end
		local has_glance_sidecar = false
		for _, candidate in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			local filetype = vim.bo[vim.api.nvim_win_get_buf(candidate)].filetype
			if filetype == "Glance" or (filetype == "aerial" and vim.w[candidate].dotfiles_glance_aerial_layout) then
				has_glance_sidecar = true
				break
			end
		end
		local config = vim.api.nvim_win_get_config(win)
		if config.relative == "" then
			return false
		end
		local cursor = vim.api.nvim_win_get_cursor(win)
		local role = vim.w[win].dotfiles_git_diff_peek_role
		return normalize(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))) == expected_path
			and cursor[1] == expected_line
			and cursor[2] == expected_col
			and has_glance_sidecar
			and role ~= "worktree"
			and role ~= "revision"
	end)
	popup_state(label)
end

local function close_glance(source_win, label)
	require("glance").actions.close()
	wait_for(label .. ": Glance close did not restore popup focus", function()
		local win = vim.api.nvim_get_current_win()
		return win == source_win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative ~= ""
	end)
	popup_state(label)
end

vim.cmd.edit(vim.fn.fnameescape(source))
local source_win = vim.api.nvim_get_current_win()
local source_buf = vim.api.nvim_get_current_buf()
wait_for("lua-language-server did not attach", function()
	return #vim.lsp.get_clients({ bufnr = source_buf }) > 0
end)

local fixtures = {
	"local same_value = 1; print(same_value)",
	"local other_value = 1",
	"print(other_value)",
}
vim.api.nvim_buf_set_lines(source_buf, 0, 0, false, fixtures)
local same_line = fixtures[1]
local same_call_col = 28
assert(same_line:sub(7, 16) == "same_value")
assert(same_line:sub(same_call_col + 1, same_call_col + 10) == "same_value")
vim.api.nvim_win_set_cursor(source_win, { 1, same_call_col })

local changedtick_settled = false
vim.defer_fn(function()
	changedtick_settled = true
end, 1500)
wait_for("LSP didChange settle timer did not finish", function()
	return changedtick_settled
end, 3000)

local client = assert(vim.lsp.get_clients({ bufnr = source_buf })[1], "LSP client is required")
local responses = vim.lsp.buf_request_sync(
	0,
	"textDocument/definition",
	vim.lsp.util.make_position_params(0, client.offset_encoding),
	3000
)
local definition
for _, response in pairs(responses or {}) do
	local result = response.result
	if result and result.uri then
		result = { result }
	end
	if type(result) == "table" and result[1] then
		local item = result[1]
		local range = assert(item.targetSelectionRange or item.range, "definition range is required")
		definition = {
			path = normalize(vim.uri_to_fname(assert(item.targetUri or item.uri, "definition URI is required"))),
			line = range.start.line + 1,
			col = range.start.character,
		}
		break
	end
end
assert(definition, "same-line LSP definition result is required")
assert(definition.path == normalize(source), "same-line definition must stay on the source path")
assert(definition.line == 1 and definition.col == 6, "same-line definition must target declaration column 6")
local original_gd = vim.iter(vim.api.nvim_buf_get_keymap(source_buf, "n")):find(function(mapping)
	return mapping.lhs == "gd"
end)
assert(original_gd and type(original_gd.callback) == "function", "source gd callback must exist before popup")

local gitsigns = require("gitsigns")
local original_diffthis = gitsigns.diffthis
local diffthis_called = false
local diffthis_base
local diffthis_error
gitsigns.diffthis = function(base, _, callback)
	diffthis_called = true
	diffthis_base = base
	local ok, err = xpcall(function()
		local revision_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(revision_buf, "gitsigns:///tmp/.git//:0:lsp.lua")
		vim.api.nvim_buf_set_lines(revision_buf, 0, -1, false, vim.api.nvim_buf_get_lines(source_buf, 0, -1, false))
		vim.bo[revision_buf].bufhidden = "wipe"
		vim.bo[revision_buf].buftype = "acwrite"
		vim.cmd("belowright vsplit")
		local revision_win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(revision_win, revision_buf)
		vim.wo[revision_win].diff = true
		vim.wo[source_win].diff = true
		vim.api.nvim_set_current_win(source_win)
		callback()
	end, debug.traceback)
	if not ok then
		diffthis_error = err
	end
end

local cases = 0
local scenario_ok, scenario_error = xpcall(function()
	press("<Space>gp")
	assert(diffthis_error == nil, diffthis_error)
	assert(
		vim.wait(10000, function()
			local worktree, revision = roles()
			return worktree == 1 and revision == 1 and vim.t.diffview_view_initialized ~= true
		end, 25),
		("Git Diff Peek did not open (stub_called=%s base=%s error=%s)"):format(
			tostring(diffthis_called),
			vim.inspect(diffthis_base),
			tostring(diffthis_error)
		)
	)
	assert(diffthis_called, "Git Diff Peek must invoke the gitsigns diffthis stub")
	popup_state("worktree open")
	assert(diffthis_base == "HEAD", "Git Diff Peek must compare the worktree against HEAD")
	cases = cases + 1

	local worktree_win = assert(popup_win("worktree"), "worktree pane is required")
	vim.api.nvim_set_current_win(worktree_win)
	vim.api.nvim_win_set_cursor(worktree_win, { 1, same_call_col })
	press("gd")
	wait_for_preview(worktree_win, normalize(source), 1, 6, "same-line self definition")
	cases = cases + 1
	close_glance(worktree_win, "same-line self definition")
	cases = cases + 1

	vim.api.nvim_win_set_cursor(worktree_win, { 3, 6 })
	press("gd")
	wait_for_preview(worktree_win, normalize(source), 2, 6, "same-file other-location definition")
	cases = cases + 1
	close_glance(worktree_win, "same-file other-location definition")
	cases = cases + 1

	local revision_win = assert(popup_win("revision"), "revision pane is required")
	vim.api.nvim_set_current_win(revision_win)
	vim.api.nvim_win_set_cursor(revision_win, { 1, same_call_col })
	press("gd")
	local revision_gd_settled = false
	vim.defer_fn(function()
		revision_gd_settled = true
	end, 500)
	wait_for("revision plain gd did not settle", function()
		return revision_gd_settled
	end, 2000)
	popup_state("revision plain gd")
	assert(vim.api.nvim_get_current_win() == revision_win, "revision plain gd must retain revision focus")
	cases = cases + 1

	local popup_buf = vim.api.nvim_win_get_buf(worktree_win)
	press("q")
	wait_for("q did not close Git Diff Peek", function()
		local worktree, revision = roles()
		return worktree == 0
			and revision == 0
			and vim.t.diffview_view_initialized ~= true
			and vim.api.nvim_get_current_win() == source_win
	end)
	local owned_desc = {
		["Close Git diff peek"] = true,
		["Open all Git diff folds"] = true,
		["Previous Git diff peek buffer"] = true,
		["Next Git diff peek buffer"] = true,
		["Move to previous Git diff pane"] = true,
		["Move to next Git diff pane"] = true,
		["Cycle Git diff panes"] = true,
	}
	wait_for("Git Diff Peek-owned buffer maps did not clean up", function()
		for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(popup_buf, "n")) do
			if owned_desc[mapping.desc] then
				return false
			end
		end
		return true
	end)
	for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(popup_buf, "n")) do
		assert(not owned_desc[mapping.desc], "Git Diff Peek-owned buffer map leaked: " .. tostring(mapping.desc))
	end
	local restored_gd = vim.iter(vim.api.nvim_buf_get_keymap(source_buf, "n")):find(function(mapping)
		return mapping.lhs == "gd"
	end)
	assert(
		restored_gd and restored_gd.callback == original_gd.callback,
		"source gd callback must survive popup cleanup"
	)
	local transition_autocmds = 0
	for _, autocmd in ipairs(vim.api.nvim_get_autocmds({})) do
		if autocmd.desc and autocmd.desc:find("Git diff peek", 1, true) then
			transition_autocmds = transition_autocmds + 1
		end
	end
	assert(transition_autocmds == 0, "Git Diff Peek autocmds must be cleaned up after q close")
	cases = cases + 1

	press("<Space>gp")
	wait_for("Git Diff Peek did not reopen", function()
		local worktree, revision = roles()
		return worktree == 1 and revision == 1 and vim.t.diffview_view_initialized ~= true
	end)
	popup_state("reopen")
	cases = cases + 1

	press("<Space>gd")
	wait_for("literal Space-gd did not hand off to Diffview", function()
		local worktree, revision = roles()
		return worktree == 0 and revision == 0 and vim.t.diffview_view_initialized == true
	end)
	cases = cases + 1
	press("<Space>gd")
	wait_for("repeated Space-gd did not restore source", function()
		return vim.t.diffview_view_initialized ~= true
			and vim.api.nvim_get_current_win() == source_win
			and vim.api.nvim_buf_get_name(0) == source
	end)
	cases = cases + 1
end, debug.traceback)

gitsigns.diffthis = original_diffthis
pcall(function()
	require("glance").actions.close()
end)
pcall(function()
	local worktree, revision = roles()
	if worktree > 0 or revision > 0 then
		require("config.git_diff_peek").toggle()
	end
end)
pcall(function()
	if vim.t.diffview_view_initialized == true then
		vim.cmd.DiffviewClose()
	end
end)
gitsigns.diffthis = original_diffthis

if not scenario_ok then
	error(scenario_error)
end
print(("Git Diff Peek definition integration: ok (%d cases)"):format(cases))
