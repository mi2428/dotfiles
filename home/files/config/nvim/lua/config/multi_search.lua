local catppuccin = require("config.catppuccin")

local M = {}

local state = {
	patterns = {},
	window_matches = {},
}

local group_names = {
	"DotfilesMultiSearch1",
	"DotfilesMultiSearch2",
	"DotfilesMultiSearch3",
	"DotfilesMultiSearch4",
	"DotfilesMultiSearch5",
	"DotfilesMultiSearch6",
}
local match_priority = 100

local function contrast_fg()
	if catppuccin.flavour == "latte" then
		return catppuccin.palette().crust
	end

	return catppuccin.palette().base
end

local function set_highlights()
	local palette = catppuccin.palette()
	local colors = {
		palette.mauve,
		palette.blue,
		palette.green,
		palette.peach,
		palette.yellow,
		palette.pink,
	}

	for index, group in ipairs(group_names) do
		vim.api.nvim_set_hl(0, group, {
			fg = contrast_fg(),
			bg = colors[index],
			bold = true,
		})
	end
end

local function clear_window_matches(winid)
	local matches = state.window_matches[winid]
	if not matches then
		return
	end

	for _, match_id in ipairs(matches) do
		pcall(vim.fn.matchdelete, match_id, winid)
	end

	state.window_matches[winid] = nil
end

local function is_supported_window(winid)
	if not vim.api.nvim_win_is_valid(winid) then
		return false
	end

	local bufnr = vim.api.nvim_win_get_buf(winid)
	local buftype = vim.bo[bufnr].buftype
	return buftype == ""
end

local function apply_window_matches(winid)
	clear_window_matches(winid)

	if not is_supported_window(winid) then
		return
	end

	local matches = {}
	for index, entry in ipairs(state.patterns) do
		local ok, match_id =
			pcall(vim.fn.matchadd, group_names[((index - 1) % #group_names) + 1], entry.pattern, match_priority, -1, {
				window = winid,
			})
		if ok and match_id then
			matches[#matches + 1] = match_id
		end
	end

	if #matches > 0 then
		state.window_matches[winid] = matches
	end
end

local function refresh_all_windows()
	for _, winid in ipairs(vim.api.nvim_list_wins()) do
		apply_window_matches(winid)
	end
end

local function set_search_register(pattern)
	vim.fn.setreg("/", pattern)
	vim.opt.hlsearch = true
end

local function find_pattern(pattern)
	for index, entry in ipairs(state.patterns) do
		if entry.pattern == pattern then
			return index
		end
	end

	return nil
end

local function remove_pattern(pattern)
	local index = find_pattern(pattern)
	if not index then
		return false
	end

	table.remove(state.patterns, index)
	refresh_all_windows()
	return true
end

local function has_patterns()
	return #state.patterns > 0
end

local function compare_pos(a, b)
	if a.line == b.line then
		return a.col - b.col
	end

	return a.line - b.line
end

local function search_candidate(pattern, backward)
	local flags = backward and "bnW" or "nW"
	local pos = vim.fn.searchpos(pattern, flags)
	local wrapped = false

	if pos[1] == 0 then
		flags = backward and "bn" or "n"
		pos = vim.fn.searchpos(pattern, flags)
		wrapped = true
	end

	if pos[1] == 0 then
		return nil
	end

	return {
		pattern = pattern,
		line = pos[1],
		col = pos[2],
		wrapped = wrapped,
	}
end

local function best_candidate(backward)
	local best = nil

	-- Prefer the nearest non-wrapped match across all active patterns so `n`
	-- and `N` still behave like native search, just over a larger match set.
	for _, entry in ipairs(state.patterns) do
		local candidate = search_candidate(entry.pattern, backward)
		if candidate then
			if not best then
				best = candidate
			elseif best.wrapped ~= candidate.wrapped then
				if not candidate.wrapped then
					best = candidate
				end
			else
				local cmp = compare_pos(candidate, best)
				if (not backward and cmp < 0) or (backward and cmp > 0) then
					best = candidate
				end
			end
		end
	end

	return best
end

local function fallback_normal(key)
	-- Native `n`/`N` raises E486 when the search register has no match.  This
	-- mapping is a no-op in that case, just as multi-search is when empty.
	pcall(vim.cmd.normal, { args = { vim.v.count1 .. key }, bang = true })
end

function M.jump(backward)
	if not has_patterns() then
		fallback_normal(backward and "N" or "n")
		return
	end

	for _ = 1, vim.v.count1 do
		local candidate = best_candidate(backward)
		if not candidate then
			return
		end

		set_search_register(candidate.pattern)
		vim.fn.cursor(candidate.line, candidate.col)
		vim.cmd.normal({ args = { "zv" }, bang = true })
	end
end

function M.add(pattern)
	if not pattern or pattern == "" then
		return
	end

	if not find_pattern(pattern) then
		state.patterns[#state.patterns + 1] = { pattern = pattern }
	end

	-- Re-apply matches even for an already tracked pattern so repeated
	-- `<leader>/` runs recover from stale window match state.
	refresh_all_windows()
	set_search_register(pattern)
end

function M.toggle_word_under_cursor()
	local word = vim.fn.expand("<cword>")
	if word == nil or word == "" then
		return
	end

	local pattern = ([[\V\<%s\>]]):format(vim.fn.escape(word, [[\]]))
	if remove_pattern(pattern) then
		return
	end

	M.add(pattern)
end

function M.input_and_add()
	local pattern = vim.fn.input({ prompt = "/" })
	if pattern == nil or pattern == "" then
		return
	end

	vim.fn.histadd("search", pattern)
	M.add(pattern)
end

function M.clear()
	state.patterns = {}
	for winid in pairs(state.window_matches) do
		clear_window_matches(winid)
	end
	state.window_matches = {}
end

function M.nohl()
	vim.cmd("nohlsearch")
	M.clear()

	-- mini.map's builtin search watcher does not reliably observe :nohlsearch
	-- (notably when invoked through <C-l>). Refresh only its integrations; the
	-- multi-window wrapper propagates this to every pane-local minimap.
	local minimap = package.loaded["mini.map"]
	if minimap and minimap.refresh then
		minimap.refresh({}, { integrations = true, lines = false, scrollbar = false })
	end
end

local function setup_nohl_abbrev(lhs)
	vim.cmd(
		("cnoreabbrev <expr> %s ((getcmdtype() ==# ':' && getcmdline() ==# '%s') ? 'DotfilesNohlsearch' : '%s')"):format(
			lhs,
			lhs,
			lhs
		)
	)
end

function M.setup()
	set_highlights()

	vim.api.nvim_create_autocmd("ColorScheme", {
		group = vim.api.nvim_create_augroup("dotfiles-multi-search-colors", { clear = true }),
		pattern = "*",
		callback = function()
			set_highlights()
			refresh_all_windows()
		end,
	})

	vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "WinEnter", "WinNew" }, {
		group = vim.api.nvim_create_augroup("dotfiles-multi-search-window-refresh", { clear = true }),
		callback = function()
			apply_window_matches(vim.api.nvim_get_current_win())
		end,
	})

	vim.api.nvim_create_autocmd("WinClosed", {
		group = vim.api.nvim_create_augroup("dotfiles-multi-search-window-cleanup", { clear = true }),
		callback = function(args)
			local winid = tonumber(args.match)
			if winid then
				state.window_matches[winid] = nil
			end
		end,
	})

	vim.api.nvim_create_user_command("DotfilesNohlsearch", function()
		M.nohl()
	end, {})

	setup_nohl_abbrev("noh")
	setup_nohl_abbrev("nohl")
	setup_nohl_abbrev("nohlsearch")

	vim.keymap.set("n", "<leader>/", function()
		M.input_and_add()
	end, { desc = "Add search highlight" })
	vim.keymap.set("n", "<leader>*", function()
		M.toggle_word_under_cursor()
	end, { desc = "Toggle highlighted word" })
	vim.keymap.set("n", "n", function()
		M.jump(false)
	end, { desc = "Next highlighted match" })
	vim.keymap.set("n", "N", function()
		M.jump(true)
	end, { desc = "Previous highlighted match" })
	vim.keymap.set("n", "<C-l>", function()
		M.nohl()
	end, { desc = "Clear search highlights" })
end

return M
