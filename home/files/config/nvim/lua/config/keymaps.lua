local map = vim.keymap.set

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
-- Use built-in buffer commands: BufferLine is lazy-loaded and unavailable early
-- in startup. Its visual order is the inverse of :bnext/:bprevious here.
local function map_buffer_cycles(bufnr)
	local opts = { nowait = true }
	if bufnr then
		opts.buffer = bufnr
	end

	map("n", "[[", "<cmd>bprevious<cr>", vim.tbl_extend("force", opts, { desc = "Previous buffer" }))
	map("n", "]]", "<cmd>bnext<cr>", vim.tbl_extend("force", opts, { desc = "Next buffer" }))
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
map("n", "<C-w>|", "<cmd>vsplit<cr>", { desc = "Vertical split" })
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
	require("fzf-lua").git_status()
end, { desc = "Git status" })
map("n", "<leader>gd", "<cmd>DiffviewOpen<cr>", { desc = "Git diff view" })
map("n", "<leader>gD", "<cmd>DiffviewClose<cr>", { desc = "Close diff view" })
map("n", "<leader>gh", "<cmd>DiffviewFileHistory %<cr>", { desc = "File history" })
map("n", "<leader>gH", "<cmd>DiffviewFileHistory<cr>", { desc = "Branch history" })
map("n", "<leader>b", function()
	require("fzf-lua").buffers()
end, { desc = "Buffers" })
map("n", "<leader>h", function()
	require("fzf-lua").oldfiles()
end, { desc = "Recent files" })
map("n", "<leader>r", function()
	require("fzf-lua").live_grep()
end, { desc = "Live grep" })

map({ "n", "v" }, "<leader>a", "<cmd>CodeCompanionActions<cr>", { desc = "CodeCompanion actions" })
map({ "n", "v" }, "<localleader>a", "<cmd>CodeCompanionChat Toggle<cr>", { desc = "Toggle CodeCompanion chat" })
map("n", "<localleader>c", "<cmd>CodeCompanionCLI<cr>", { desc = "Open CodeCompanion CLI" })
map("v", "ga", "<cmd>CodeCompanionChat Add<cr>", { desc = "Add selection to CodeCompanion chat" })
