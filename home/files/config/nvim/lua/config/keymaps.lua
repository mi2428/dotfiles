local map = vim.keymap.set

local pane_resize_step = 5
local pane_resize_repeat = "<Plug>(dotfiles-pane-resize-repeat)"
local pane_resize_repeat_time = 500
local pane_resize_saved_timeoutlen

local opposite_direction = {
	h = "l",
	j = "k",
	k = "j",
	l = "h",
}

local function pane_neighbor(direction)
	local current_win = vim.api.nvim_get_current_win()
	local neighbor_win = vim.fn.win_getid(vim.fn.winnr(direction))
	if neighbor_win == 0 or neighbor_win == current_win or not vim.api.nvim_win_is_valid(neighbor_win) then
		return nil
	end
	return neighbor_win
end

local function resize_pane_toward(direction)
	local current_win = vim.api.nvim_get_current_win()
	local resized_win = pane_neighbor(direction)
	if not resized_win then
		-- tmux still moves the separator in the requested direction when the
		-- focused pane is at an outer edge. In that case it shrinks the focused
		-- pane using the separator on the opposite side.
		if not pane_neighbor(opposite_direction[direction]) then
			return
		end
		resized_win = current_win
	end

	if direction == "h" or direction == "l" then
		local width = vim.api.nvim_win_get_width(resized_win)
		vim.api.nvim_win_set_width(resized_win, math.max(vim.o.winminwidth, width - pane_resize_step))
	else
		local height = vim.api.nvim_win_get_height(resized_win)
		vim.api.nvim_win_set_height(resized_win, math.max(vim.o.winminheight, height - pane_resize_step))
	end
end

local function enter_pane_resize_repeat()
	if pane_resize_saved_timeoutlen == nil then
		pane_resize_saved_timeoutlen = vim.o.timeoutlen
	end
	vim.o.timeoutlen = pane_resize_repeat_time
end

local function leave_pane_resize_repeat()
	if pane_resize_saved_timeoutlen == nil then
		return
	end
	if vim.o.timeoutlen == pane_resize_repeat_time then
		vim.o.timeoutlen = pane_resize_saved_timeoutlen
	end
	pane_resize_saved_timeoutlen = nil
end

local function toggle_diffview()
	if vim.t.diffview_view_initialized then
		vim.cmd.DiffviewClose()
	else
		vim.cmd.DiffviewOpen()
	end
end

local function toggle_gitsigns_diff_peek()
	local tabpage = vim.api.nvim_get_current_tabpage()
	local current_win = vim.api.nvim_get_current_win()
	local revision_wins = {}
	local return_win
	local current_is_revision = false

	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
		local buf = vim.api.nvim_win_get_buf(win)
		if vim.api.nvim_buf_get_name(buf):match("^gitsigns://") then
			revision_wins[#revision_wins + 1] = win
			current_is_revision = current_is_revision or win == current_win
		elseif win ~= current_win and vim.wo[win].diff then
			return_win = win
		end
	end

	if #revision_wins > 0 then
		local current_is_diff = vim.wo.diff
		for _, win in ipairs(revision_wins) do
			if vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_close(win, true)
			end
		end
		if current_is_revision and return_win and vim.api.nvim_win_is_valid(return_win) then
			vim.api.nvim_set_current_win(return_win)
		end
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
			if vim.wo[win].diff then
				vim.wo[win].diff = false
			end
		end
		if current_is_revision or current_is_diff then
			return
		end
	end

	if vim.wo.diff then
		vim.notify("Already in a non-Gitsigns diff view", vim.log.levels.INFO)
		return
	end

	require("gitsigns").diffthis(nil, { vertical = true })
end

local function bufferline_group_action()
	local groups = {}
	for _, group in ipairs(require("bufferline.groups").get_names(true)) do
		if group ~= "pinned" and group ~= "ungrouped" then
			groups[#groups + 1] = group
		end
	end
	if #groups == 0 then
		return
	end

	vim.ui.select({ "toggle", "close" }, { prompt = "Bufferline group action" }, function(action)
		if not action then
			return
		end
		local command = action == "toggle" and "BufferLineGroupToggle" or "BufferLineGroupClose"

		vim.ui.select(groups, { prompt = "Bufferline group" }, function(group)
			if group then
				vim.cmd(command .. " " .. group)
			end
		end)
	end)
end

map("n", "<C-l>", "<cmd>nohlsearch<cr>", { desc = "Clear search highlight" })
map("x", "p", [["_dP]], { desc = "Paste without yanking replaced text" })

map("n", "-", function()
	require("oil").open()
end, { desc = "Open parent directory" })
-- Keep buffer cycling on doubled brackets so a lone `[` or `]` does not wait
-- for a longer mapping. This deliberately replaces Neovim's section motions.
-- Follow Bufferline's visual order, including buffers moved by the user.
local function cycle_bufferline(command)
	-- Bufferline rebuilds its component list while rendering the tabline. A
	-- picker can enter a newly-created buffer before that render happens, which
	-- leaves BufferLineCycle* unable to find the current buffer.
	vim.cmd.redrawtabline()
	vim.cmd(command)
end

local function map_buffer_cycles(bufnr)
	local opts = { nowait = true }
	if bufnr then
		opts.buffer = bufnr
	end

	map("n", "[[", function()
		cycle_bufferline("BufferLineCyclePrev")
	end, vim.tbl_extend("force", opts, { desc = "Previous buffer" }))
	map("n", "]]", function()
		cycle_bufferline("BufferLineCycleNext")
	end, vim.tbl_extend("force", opts, { desc = "Next buffer" }))
end

map_buffer_cycles()
-- Some ftplugins (notably Go's) install buffer-local [[ / ]] section motions,
-- which take precedence over the global mappings above. Reapply asynchronously
-- after FileType/BufEnter processing so the buffer-cycle mappings win.
vim.api.nvim_create_autocmd({ "BufEnter", "FileType" }, {
	group = vim.api.nvim_create_augroup("dotfiles-buffer-cycle-keymaps", { clear = true }),
	callback = function(args)
		vim.schedule(function()
			if vim.api.nvim_buf_is_valid(args.buf) and vim.bo[args.buf].buftype == "" then
				map_buffer_cycles(args.buf)
			end
		end)
	end,
})
map("n", "[b", "<cmd>BufferLineCyclePrev<cr>", { desc = "Previous buffer" })
map("n", "]b", "<cmd>BufferLineCycleNext<cr>", { desc = "Next buffer" })
map("n", "[t", "<cmd>tabprevious<cr>", { desc = "Previous tab" })
map("n", "]t", "<cmd>tabnext<cr>", { desc = "Next tab" })
map("n", "<C-w>p", "<cmd>BufferLineTogglePin<cr>", { desc = "Toggle buffer pin" })
map("n", "<C-w>f", "<cmd>BufferLinePick<cr>", { desc = "Pick buffer" })
map("n", "<C-w>d", "<cmd>BufferLinePickClose<cr>", { desc = "Pick buffer to close" })
map("n", "<C-w>,", "<cmd>BufferLineMovePrev<cr>", { desc = "Move buffer left" })
map("n", "<C-w>.", "<cmd>BufferLineMoveNext<cr>", { desc = "Move buffer right" })
map("n", "<C-w>g", bufferline_group_action, { desc = "Bufferline group action" })
map("n", "<C-w>-", "<cmd>split<cr>", { desc = "Horizontal split" })
map("n", "<C-w>\\", "<cmd>vsplit<cr>", { desc = "Vertical split" })
map("n", "<C-w>h", "<cmd>wincmd h<cr>", { desc = "Move to left pane" })
map("n", "<C-w>j", "<cmd>wincmd j<cr>", { desc = "Move to lower pane" })
map("n", "<C-w>k", "<cmd>wincmd k<cr>", { desc = "Move to upper pane" })
map("n", "<C-w>l", "<cmd>wincmd l<cr>", { desc = "Move to right pane" })
-- A complete <Plug> mapping that is also a prefix lets the next H/J/K/L use
-- the same resize table without another <C-w>. A different key resolves this
-- mapping, leaves repeat mode, and is then handled normally. Its 500 ms wait
-- matches tmux's default `repeat-time` without changing the normal timeoutlen.
map("n", pane_resize_repeat, leave_pane_resize_repeat)
for key, spec in pairs({
	H = { direction = "h", desc = "Resize pane left" },
	J = { direction = "j", desc = "Resize pane down" },
	K = { direction = "k", desc = "Resize pane up" },
	L = { direction = "l", desc = "Resize pane right" },
}) do
	local action = "<Plug>(dotfiles-pane-resize-" .. spec.direction .. ")"
	map("n", action, function()
		resize_pane_toward(spec.direction)
		enter_pane_resize_repeat()
	end)
	map("n", pane_resize_repeat .. key, action .. pane_resize_repeat, { remap = true })
	map("n", "<C-w>" .. key, action .. pane_resize_repeat, { desc = spec.desc, remap = true })
end
for i = 1, 9 do
	map("n", "<C-w>" .. i, "<cmd>BufferLineGoToBuffer " .. i .. "<cr>", { desc = "Go to buffer " .. i })
end

map("n", "<leader>f", function()
	require("fzf-lua").files({ cwd = vim.fs.root(0, ".git") or vim.fn.getcwd() })
end, { desc = "Find files from repo root" })
map("n", "<leader>d", function()
	require("fzf-lua").files({ cwd = vim.fn.getcwd() })
end, { desc = "Find files from current directory" })
map("n", "<leader>g", function()
	require("fzf-lua").git_files()
end, { desc = "Find git files" })
map("n", "<leader>G", function()
	local review = require("config.review")
	if review.state then
		review.open(false)
	else
		require("fzf-lua").git_status()
	end
end, { desc = "Git status / review diff" })
map("n", "<leader>gd", toggle_diffview, { desc = "Toggle Git diff view" })
map("n", "<leader>gp", toggle_gitsigns_diff_peek, { desc = "Toggle Git diff peek" })
map("n", "<leader>gh", "<cmd>DiffviewFileHistory %<cr>", { desc = "File history" })
map("n", "<leader>gH", "<cmd>DiffviewFileHistory<cr>", { desc = "Branch history" })
map("n", "<leader>b", function()
	require("fzf-lua").buffers()
end, { desc = "Buffers" })
map("n", "<leader>h", function()
	require("fzf-lua").oldfiles()
end, { desc = "Recent files" })
map("n", "<leader>r", function()
	require("fzf-lua").live_grep({ headers = false })
end, { desc = "Live grep" })

-- CodeCompanion used to own the editor chat and CLI mappings here. Herdr now
-- keeps the Codex session, while config.herdr sends visual selections directly;
-- keeping these mappings disabled also avoids requiring the codex-acp adapter.
-- map({ "n", "v" }, "<leader>a", "<cmd>CodeCompanionActions<cr>", { desc = "CodeCompanion actions" })
-- map({ "n", "v" }, "<localleader>a", "<cmd>CodeCompanionChat Toggle<cr>", { desc = "Toggle CodeCompanion chat" })
-- map("n", "<localleader>c", "<cmd>CodeCompanionCLI<cr>", { desc = "Open CodeCompanion CLI" })
-- map("v", "ga", "<cmd>CodeCompanionChat Add<cr>", { desc = "Add selection to CodeCompanion chat" })
map("x", "<leader>h", function()
	require("config.herdr").prompt_selection()
end, { desc = "Prompt Herdr agent about selection" })
map("n", "<leader>H", function()
	require("config.herdr").select_agent()
end, { desc = "Select Herdr AI agent" })
