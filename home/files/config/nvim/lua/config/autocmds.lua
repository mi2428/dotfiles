local autocmd = vim.api.nvim_create_autocmd
local augroup = vim.api.nvim_create_augroup

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

autocmd("TextYankPost", {
	desc = "Highlight when yanking text",
	group = augroup("dotfiles-highlight-yank", { clear = true }),
	callback = function()
		vim.highlight.on_yank()
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
		map("n", "gD", vim.lsp.buf.declaration, "LSP declaration")
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
