local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")

dofile(vim.fs.joinpath(nvim_root, "lua/config/autocmds.lua"))
vim.api.nvim_exec_autocmds("LspAttach", {
	buffer = 0,
	data = { client_id = -1 },
})

local function mapping(lhs)
	local found = vim.iter(vim.api.nvim_buf_get_keymap(0, "n")):find(function(item)
		return item.lhs == lhs
	end)
	assert(found and type(found.callback) == "function", lhs .. " must have a Lua callback")
	return found.callback
end

vim.api.nvim_buf_set_lines(0, 0, -1, false, {
	"start",
	"hint",
	"information",
	"warning",
	"error",
})
local namespace = vim.api.nvim_create_namespace("dotfiles-diagnostic-navigation-test")
vim.diagnostic.set(namespace, 0, {
	{ lnum = 1, col = 0, severity = vim.diagnostic.severity.HINT, message = "skip hint" },
	{ lnum = 2, col = 0, severity = vim.diagnostic.severity.INFO, message = "visit information" },
	{ lnum = 3, col = 0, severity = vim.diagnostic.severity.WARN, message = "visit warning" },
	{ lnum = 4, col = 0, severity = vim.diagnostic.severity.ERROR, message = "visit error" },
})

vim.api.nvim_win_set_cursor(0, { 1, 0 })
mapping("]d")()
assert(vim.api.nvim_win_get_cursor(0)[1] == 3, "]d must skip HINT and land on INFO")
mapping("]d")()
assert(vim.api.nvim_win_get_cursor(0)[1] == 4, "]d must continue from INFO to WARN")
mapping("]d")()
assert(vim.api.nvim_win_get_cursor(0)[1] == 5, "]d must continue from WARN to ERROR")
mapping("[d")()
assert(vim.api.nvim_win_get_cursor(0)[1] == 4, "[d must move backward from ERROR to WARN")

print("diagnostic navigation regression: ok")
