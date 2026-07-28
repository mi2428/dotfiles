local autocmd = vim.api.nvim_create_autocmd
local augroup = vim.api.nvim_create_augroup
local workspace_mode = vim.env.NVIM_WORKSPACE_MODE == "1"

local startup_directory
if vim.fn.argc() == 1 then
	local argument = vim.fn.fnamemodify(vim.fn.argv(0), ":p")
	if vim.fn.isdirectory(argument) == 1 then
		startup_directory = argument
	end
end

local function is_ansible_yaml_path(path)
	local patterns = {
		"/group_vars/.*%.ya?ml$",
		"/host_vars/.*%.ya?ml$",
		"/roles/[^/]+/tasks/.*%.ya?ml$",
		"/roles/[^/]+/handlers/.*%.ya?ml$",
		"/roles/[^/]+/defaults/.*%.ya?ml$",
		"/roles/[^/]+/vars/.*%.ya?ml$",
		"/playbooks/.*%.ya?ml$",
		"/ansible/.*%.ya?ml$",
		"/playbook%.ya?ml$",
		"/site%.ya?ml$",
		"/main%.ya?ml$",
	}

	for _, pattern in ipairs(patterns) do
		if path:match(pattern) then
			return true
		end
	end

	return false
end

autocmd("BufWritePre", {
	desc = "Create missing parent directories before writing",
	group = augroup("dotfiles-create-parent-directory", { clear = true }),
	callback = function(args)
		if vim.bo[args.buf].buftype ~= "" then
			return
		end

		local filename = vim.api.nvim_buf_get_name(args.buf)
		local directory = filename ~= "" and vim.fs.dirname(filename) or nil
		if not directory or vim.fn.isdirectory(directory) == 1 then
			return
		end

		local confirmed = vim.v.cmdbang == 1
			or vim.fn.confirm(("Create missing directory?\n%s"):format(directory), "&Yes\n&No", 2) == 1
		if confirmed then
			vim.fn.mkdir(directory, "p")
		end
	end,
})

autocmd("TextYankPost", {
	desc = "Highlight when yanking text",
	group = augroup("dotfiles-highlight-yank", { clear = true }),
	callback = function()
		vim.highlight.on_yank()
	end,
})

local function is_empty_editor_buffer(buf)
	return vim.bo[buf].buftype == ""
		and vim.bo[buf].filetype == ""
		and vim.api.nvim_buf_get_name(buf) == ""
		and not vim.bo[buf].modified
		and vim.api.nvim_buf_line_count(buf) == 1
		and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ""
end

local function is_empty_editor_window(win)
	return is_empty_editor_buffer(vim.api.nvim_win_get_buf(win))
end

local auxiliary_filetypes = {
	aerial = true,
	["aerial-nav"] = true,
	minimap = true,
	snacks_layout_box = true,
	snacks_terminal = true,
}

local function is_auxiliary_buffer(buf)
	return auxiliary_filetypes[vim.bo[buf].filetype] == true
end

local function is_auxiliary_window(win)
	return is_auxiliary_buffer(vim.api.nvim_win_get_buf(win))
end

local function is_user_buffer(buf)
	return vim.api.nvim_buf_is_valid(buf)
		and vim.bo[buf].buflisted
		and vim.bo[buf].buftype == ""
		and not is_auxiliary_buffer(buf)
		and not is_empty_editor_buffer(buf)
end

local function has_user_buffer()
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if is_user_buffer(buf) then
			return true
		end
	end
	return false
end

local function should_exit_after_quit(quitting_win)
	local has_auxiliary_window = false
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local is_auxiliary = is_auxiliary_window(win)
		if is_auxiliary then
			has_auxiliary_window = true
		elseif vim.api.nvim_win_get_config(win).relative == "" then
			if win ~= quitting_win and not is_empty_editor_window(win) then
				return false
			end
		end
	end

	return has_auxiliary_window
end

local function has_modified_user_buffer()
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].modified and not is_auxiliary_buffer(buf) then
			return true
		end
	end
	return false
end

local function is_user_editor_window(win)
	return vim.api.nvim_win_get_config(win).relative == "" and not is_auxiliary_window(win)
end

local auxiliary_exit_pending = false

local function exit_after_quit()
	if auxiliary_exit_pending then
		return
	end

	auxiliary_exit_pending = true
	local function try_exit(attempts_left)
		-- QuitPre still runs inside the original :quit command. A short timer keeps
		-- :quitall from being nested in that command while auxiliary layouts tear down.
		vim.defer_fn(function()
			if has_modified_user_buffer() then
				auxiliary_exit_pending = false
				return
			end

			local ok, err = pcall(vim.cmd, "quitall!")
			if not ok then
				auxiliary_exit_pending = false
				vim.notify(("Failed to exit Neovim: %s"):format(err), vim.log.levels.ERROR)
				return
			end

			if attempts_left > 1 then
				try_exit(attempts_left - 1)
			else
				auxiliary_exit_pending = false
				vim.notify("Failed to exit Neovim after closing the last editor", vim.log.levels.ERROR)
			end
		end, 20)
	end

	try_exit(3)
end

autocmd("QuitPre", {
	desc = "Exit Neovim when quitting the last editor window leaves only auxiliary windows",
	group = augroup("dotfiles-quit-with-only-auxiliary-windows", { clear = true }),
	callback = function()
		local win = vim.api.nvim_get_current_win()
		if is_user_editor_window(win) and should_exit_after_quit(win) then
			exit_after_quit()
		end
	end,
})

autocmd("BufDelete", {
	desc = "Exit Neovim after deleting the last user buffer",
	group = augroup("dotfiles-quit-after-last-buffer", { clear = true }),
	callback = function(args)
		if not is_user_buffer(args.buf) then
			return
		end

		-- BufDelete fires before the buffer leaves the list and before buffer
		-- deletion helpers install their replacement buffer.
		vim.schedule(function()
			if not has_user_buffer() then
				exit_after_quit()
			end
		end)
	end,
})

autocmd("VimEnter", {
	desc = "Open a file picker for a directory argument",
	group = augroup("dotfiles-directory-argument-picker", { clear = true }),
	callback = function()
		if not startup_directory or #vim.api.nvim_list_uis() == 0 then
			return
		end

		vim.schedule(function()
			if vim.bo.filetype == "oil" then
				local oil_buf = vim.api.nvim_get_current_buf()
				vim.cmd.enew()
				if vim.api.nvim_buf_is_valid(oil_buf) then
					vim.api.nvim_buf_delete(oil_buf, { force = true })
				end
			end

			local editor_window = vim.api.nvim_get_current_win()
			require("fzf-lua").files({ cwd = startup_directory })

			if workspace_mode then
				local fzf_window = vim.api.nvim_get_current_win()
				Snacks.explorer({ focus = false, watch = true })
				require("config.sidebar").open_aerial({ source_win = editor_window })
				vim.schedule(function()
					require("config.terminal").toggle()
					if vim.api.nvim_win_is_valid(editor_window) then
						vim.api.nvim_set_current_win(editor_window)
					end
					if not vim.api.nvim_win_is_valid(fzf_window) then
						return
					end
					local buffer = vim.api.nvim_win_get_buf(fzf_window)
					if vim.bo[buffer].filetype ~= "fzf" then
						return
					end
					vim.api.nvim_set_current_win(fzf_window)
					vim.cmd.startinsert()
				end)
			end
		end)
	end,
})

autocmd({ "BufNewFile", "BufRead" }, {
	pattern = "*.go",
	group = augroup("dotfiles-go-tabs", { clear = true }),
	callback = function()
		vim.opt_local.expandtab = false
		vim.opt_local.tabstop = 4
		vim.opt_local.shiftwidth = 4
		vim.opt_local.softtabstop = 4
	end,
})

autocmd("FileType", {
	pattern = "yaml",
	group = augroup("dotfiles-ansible-filetype", { clear = true }),
	callback = function(args)
		local path = vim.api.nvim_buf_get_name(args.buf)
		if is_ansible_yaml_path(path) then
			vim.bo[args.buf].filetype = "yaml.ansible"
		end
	end,
})

autocmd({ "BufNewFile", "BufRead" }, {
	pattern = {
		"*/templates/*.tpl",
		"*/templates/*.yaml",
		"*/templates/*.yml",
		"*/values*.yaml",
		"*/values*.yml",
		"*/Chart.yaml",
	},
	group = augroup("dotfiles-helm-filetype", { clear = true }),
	callback = function(args)
		vim.bo[args.buf].filetype = "helm"
	end,
})

autocmd({ "BufNewFile", "BufRead" }, {
	pattern = "*.yang",
	group = augroup("dotfiles-yang-filetype", { clear = true }),
	callback = function(args)
		vim.bo[args.buf].filetype = "yang"
	end,
})

autocmd("LspAttach", {
	group = augroup("dotfiles-lsp-attach", { clear = true }),
	callback = function(args)
		local client = vim.lsp.get_client_by_id(args.data.client_id)
		local map = function(mode, lhs, rhs, desc)
			vim.keymap.set(mode, lhs, rhs, { buffer = args.buf, desc = desc })
		end
		local diagnostic_jump = function(count)
			return function()
				vim.diagnostic.jump({
					count = count,
					severity = { min = vim.diagnostic.severity.INFO },
				})
			end
		end
		local function glance_open(method, fallback)
			return function()
				local ok, glance = pcall(require, "glance")
				if ok then
					glance.actions.open(method)
					return
				end

				fallback()
			end
		end

		map("n", "gd", glance_open("definitions", vim.lsp.buf.definition), "Glance definitions")
		map("n", "gD", glance_open("definitions", vim.lsp.buf.definition), "Glance definitions")
		map("n", "gr", glance_open("references", vim.lsp.buf.references), "Glance references")
		map("n", "gI", glance_open("implementations", vim.lsp.buf.implementation), "Glance implementations")
		map("n", "gY", glance_open("type_definitions", vim.lsp.buf.type_definition), "Glance type definitions")
		map("n", "K", vim.lsp.buf.hover, "LSP hover")
		map("n", "<leader>rn", vim.lsp.buf.rename, "LSP rename")
		map({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, "LSP code action")
		map("n", "<leader>ds", vim.diagnostic.open_float, "Line diagnostics")
		map("n", "[d", diagnostic_jump(-1), "Previous error, warning, or information")
		map("n", "]d", diagnostic_jump(1), "Next error, warning, or information")

		if client and client:supports_method("textDocument/inlayHint") then
			vim.lsp.inlay_hint.enable(true, { bufnr = args.buf })
		end
	end,
})
