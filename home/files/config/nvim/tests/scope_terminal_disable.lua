local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
vim.opt.runtimepath:prepend(nvim_root)
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")

local specs = dofile(vim.fs.joinpath(nvim_root, "lua/plugins/scope.lua"))
local original_indentscope = package.loaded["mini.indentscope"]
package.loaded["mini.indentscope"] = {
	gen_animation = {
		none = function()
			return function() end
		end,
	},
	setup = function() end,
}
specs[1].config()
package.loaded["mini.indentscope"] = original_indentscope

local function new_filetype_buffer(filetype)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].filetype = filetype
	vim.api.nvim_exec_autocmds("FileType", { buffer = buf })
	return buf
end

local code_buf = new_filetype_buffer("lua")
assert(vim.b[code_buf].miniindentscope_disable ~= true, "code buffers must retain indent scopes")

local terminal_buf = new_filetype_buffer("snacks_terminal")
assert(vim.b[terminal_buf].miniindentscope_disable == true, "Snacks terminals must disable indent scopes")

print("terminal indentscope disable regression: ok")
