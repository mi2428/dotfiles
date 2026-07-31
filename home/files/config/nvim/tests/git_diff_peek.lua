local source_win = vim.api.nvim_get_current_win()
local source_buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_name(source_buf, "/tmp/dotfiles-git-diff-peek.lua")
vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, {
	"local value = 1",
	"",
	"return value",
})
vim.api.nvim_win_set_cursor(source_win, { 3, 0 })

package.loaded.gitsigns = {
	diffthis = function(_, _, callback)
		local revision_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(revision_buf, "gitsigns:///tmp/.git//:dotfiles-git-diff-peek.lua")
		vim.api.nvim_buf_set_lines(revision_buf, 0, -1, false, {
			"local value = 0",
			"",
			"return value",
		})
		vim.bo[revision_buf].bufhidden = "wipe"
		vim.cmd("aboveleft vsplit")
		local revision_win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(revision_win, revision_buf)
		vim.wo[revision_win].diff = true
		vim.wo[source_win].diff = true
		vim.api.nvim_set_current_win(source_win)
		callback()
	end,
}

local peek = require("config.git_diff_peek")
peek.toggle()

local source_float
local revision_float
local root_float
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
	local config = vim.api.nvim_win_get_config(win)
	local buf = vim.api.nvim_win_get_buf(win)
	if config.relative ~= "" and vim.wo[win].diff then
		if buf == source_buf then
			source_float = win
		elseif vim.startswith(vim.api.nvim_buf_get_name(buf), "gitsigns://") then
			revision_float = win
		end
	elseif config.relative == "editor" and vim.bo[buf].filetype == "snacks_layout_box" then
		root_float = win
	end
end

assert(source_float, "the worktree diff pane must be a floating window")
assert(revision_float, "the revision diff pane must be a floating window")
assert(root_float, "the diff panes must have a shared floating layout root")
assert(not vim.wo[source_win].diff, "the underlying editor window must leave diff mode")
assert(
	vim.api.nvim_win_get_config(source_float).relative == "win"
		and vim.api.nvim_win_get_config(revision_float).relative == "win",
	"both diff panes must be placed inside the shared popup"
)
assert(vim.api.nvim_get_current_win() == source_float, "the popup must focus the editable worktree pane")
assert(vim.api.nvim_win_get_cursor(source_float)[1] == 3, "the worktree pane must preserve the source cursor")

local close_map = vim.iter(vim.api.nvim_buf_get_keymap(source_buf, "n")):find(function(mapping)
	return mapping.desc == "Close Git diff peek"
end)
assert(close_map, "the popup must install its temporary close mapping")

peek.toggle()
assert(
	vim.wait(1000, function()
		return vim.api.nvim_get_current_win() == source_win
			and vim.iter(vim.api.nvim_list_wins()):all(function(win)
				return vim.api.nvim_win_get_config(win).relative == "" or not vim.wo[win].diff
			end)
			and vim.iter(vim.api.nvim_buf_get_keymap(source_buf, "n")):all(function(mapping)
				return mapping.desc ~= "Close Git diff peek"
			end)
	end),
	"closing the popup must restore the source editor"
)
assert(
	vim.iter(vim.api.nvim_buf_get_keymap(source_buf, "n")):all(function(mapping)
		return mapping.desc ~= "Close Git diff peek"
	end),
	"the popup close mapping must be removed from the source buffer"
)

print("Git diff peek popup regression: ok")
