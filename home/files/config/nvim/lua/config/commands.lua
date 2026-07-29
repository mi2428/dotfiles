local M = {}

local function abbrev_excmd(lhs, rhs, opts)
	opts = vim.tbl_extend("force", opts or {}, { expr = true })
	vim.keymap.set("ca", lhs, function()
		if vim.fn.getcmdtype() == ":" and vim.fn.getcmdline() == lhs then
			return rhs
		end

		return lhs
	end, opts)
end

abbrev_excmd("qw", "wq", { desc = "Fix :qw typo" })

local function is_empty_buffer(buf)
	return vim.bo[buf].buftype == ""
		and vim.api.nvim_buf_get_name(buf) == ""
		and not vim.bo[buf].modified
		and vim.api.nvim_buf_line_count(buf) == 1
		and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ""
end

local function is_user_buffer(buf)
	return vim.api.nvim_buf_is_valid(buf)
		and (vim.api.nvim_buf_is_loaded(buf) or vim.bo[buf].buflisted)
		and vim.bo[buf].buftype == ""
		and not is_empty_buffer(buf)
end

local function add_layout_buffers(owned, layout)
	if not layout then
		return
	end
	for _, window in ipairs(layout.windows or {}) do
		if window.id and vim.api.nvim_win_is_valid(window.id) then
			owned[vim.api.nvim_win_get_buf(window.id)] = true
		end
	end
	if type(layout.files) == "function" then
		local ok, files = pcall(layout.files, layout)
		if ok then
			for _, file in ipairs(files) do
				if file and file.bufnr then
					owned[file.bufnr] = true
				end
			end
		end
	end
end

local function diffview_owned_buffers(view)
	local owned = {}
	add_layout_buffers(owned, view.cur_layout)
	local sets = view.files and view.files.sets or {}
	for _, entries in pairs(sets) do
		for _, entry in ipairs(entries) do
			add_layout_buffers(owned, entry.layout)
		end
	end
	return owned
end

local function current_diffview()
	local ok, lib = pcall(require, "diffview.lib")
	if not ok then
		return
	end
	local got_view, view = pcall(lib.get_current_view)
	return got_view and view or nil
end

local function has_user_buffer_outside_diffview(view)
	local owned = diffview_owned_buffers(view)
	for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
		if tab ~= view.tabpage then
			for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
				if is_user_buffer(vim.api.nvim_win_get_buf(win)) then
					return true
				end
			end
		end
	end
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if is_user_buffer(buf) and not owned[buf] then
			return true
		end
	end
	return false
end

function M.should_confirm_quit_all()
	local has_user_buffer = false
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if is_user_buffer(buf) then
			has_user_buffer = true
			break
		end
	end
	if not has_user_buffer then
		return false
	end

	local view = current_diffview()
	return not view or has_user_buffer_outside_diffview(view)
end

vim.api.nvim_create_user_command("DotfilesQuitAll", function(args)
	if not M.should_confirm_quit_all() then
		vim.cmd({ cmd = "quitall", bang = true })
		return
	end
	local choice = vim.fn.input({
		prompt = "Quit all Neovim windows? (Y/n): ",
		cancelreturn = "n",
	})
	choice = vim.trim(choice):lower()
	if choice == "" or choice == "y" or choice == "yes" then
		vim.cmd({ cmd = "quitall", bang = args.bang })
	end
end, { bang = true, desc = "Quit all Neovim windows after confirmation" })

for _, command in ipairs({ "qa", "qall", "quitall" }) do
	abbrev_excmd(command, "DotfilesQuitAll", { desc = "Confirm before :" .. command })
end

vim.api.nvim_create_user_command("SudoWriteCurrentBuffer", function()
	local file = vim.api.nvim_buf_get_name(0)
	if file == "" then
		vim.notify("No file name for current buffer", vim.log.levels.ERROR)
		return
	end

	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local content = table.concat(lines, "\n")

	if vim.bo.endofline then
		content = content .. "\n"
	end

	local result = vim.fn.system({ "sudo", "tee", file }, content)
	if vim.v.shell_error ~= 0 then
		vim.notify(result, vim.log.levels.ERROR)
		return
	end

	vim.cmd.edit()
end, {})

return M
