local autocmd = vim.api.nvim_create_autocmd
local augroup = vim.api.nvim_create_augroup

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

			require("fzf-lua").files({ cwd = startup_directory })
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
		map("n", "[d", vim.diagnostic.goto_prev, "Previous diagnostic")
		map("n", "]d", vim.diagnostic.goto_next, "Next diagnostic")

		if client and client:supports_method("textDocument/inlayHint") then
			vim.lsp.inlay_hint.enable(true, { bufnr = args.buf })
		end
	end,
})
