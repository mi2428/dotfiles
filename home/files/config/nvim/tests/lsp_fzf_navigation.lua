local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")

local calls = {}
package.loaded["fzf-lua"] = {
	lsp_incoming_calls = function(opts)
		calls[#calls + 1] = { picker = "incoming_calls", opts = opts }
	end,
	lsp_references = function(opts)
		calls[#calls + 1] = { picker = "references", opts = opts }
	end,
}

local supports_call_hierarchy = false
local original_get_clients = vim.lsp.get_clients
local bufnr = vim.api.nvim_get_current_buf()
vim.lsp.get_clients = function(opts)
	if opts == nil then
		return original_get_clients()
	end
	assert(opts.bufnr == bufnr, "LSP capability lookup must be buffer-local")
	return {
		{
			supports_method = function(_, method, bufnr)
				assert(method == vim.lsp.protocol.Methods.textDocument_prepareCallHierarchy)
				assert(bufnr == vim.api.nvim_get_current_buf())
				return supports_call_hierarchy
			end,
		},
	}
end

dofile(vim.fs.joinpath(nvim_root, "lua/config/autocmds.lua"))
vim.api.nvim_exec_autocmds("LspAttach", {
	buffer = bufnr,
	data = { client_id = -1 },
})

local function mapping(lhs)
	local found = vim.iter(vim.api.nvim_buf_get_keymap(0, "n")):find(function(item)
		return item.lhs == lhs
	end)
	assert(found and type(found.callback) == "function", lhs .. " must have a Lua callback")
	return found
end

local gr = mapping("gr")
local gR = mapping("gR")
assert(gr.desc == "LSP callers (fzf)", "gr description must identify the caller picker")
assert(gR.desc == "LSP references (fzf)", "gR description must identify the references picker")

supports_call_hierarchy = true
gr.callback()
assert(#calls == 1 and calls[1].picker == "incoming_calls", "gr must use incoming calls when supported")
assert(calls[1].opts.jump1 == false, "gr must show fzf even for one caller")
assert(calls[1].opts.prompt == "Callers> ", "gr must label the incoming-call picker")

supports_call_hierarchy = false
gr.callback()
assert(#calls == 2 and calls[2].picker == "references", "gr must fall back to semantic references")
assert(calls[2].opts.includeDeclaration == false, "gr fallback must exclude the declaration")
assert(calls[2].opts.jump1 == false, "gr fallback must show fzf even for one reference")
assert(calls[2].opts.prompt == "References (caller fallback)> ", "gr fallback must be labeled honestly")

gR.callback()
assert(#calls == 3 and calls[3].picker == "references", "gR must always use semantic references")
assert(calls[3].opts.includeDeclaration == true, "gR must include the declaration")
assert(calls[3].opts.jump1 == false, "gR must show fzf even for one reference")
assert(calls[3].opts.prompt == "References> ", "gR must label the references picker")

vim.lsp.get_clients = original_get_clients
print("LSP fzf navigation regression: ok")
