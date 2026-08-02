local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
vim.opt.runtimepath:prepend(nvim_root)
package.path = vim.fs.joinpath(nvim_root, "lua/?.lua") .. ";" .. package.path
package.loaded["config.fzf"] = {
	ui_opts = function()
		return {}
	end,
	color_spec = function()
		return ""
	end,
}
local calls = {}
package.loaded["fzf-lua.actions"] = {
	file_vsplit = function()
		calls[#calls + 1] = "vsplit"
	end,
}
local specs = dofile(vim.fs.joinpath(nvim_root, "lua/plugins/core.lua"))
local spec = vim.iter(specs):find(function(item)
	return item[1] == "ibhagwan/fzf-lua"
end)
local action = spec.opts.actions.files["ctrl-v"]
local underlay_callback
package.loaded["config.git_diff_peek"] = {
	with_underlay = function(callback)
		calls[#calls + 1] = "underlay"
		underlay_callback = callback
		return true
	end,
}
action({}, {})
assert(vim.deep_equal(calls, { "underlay" }), "popup action must wait for underlay restoration")
underlay_callback()
underlay_callback()
assert(vim.deep_equal(calls, { "underlay", "vsplit" }), "popup action must split once after underlay restoration")
calls = {}
package.loaded["config.git_diff_peek"] = {
	with_underlay = function()
		return false
	end,
}
action({}, {})
assert(vim.deep_equal(calls, { "vsplit" }), "ordinary action must split immediately")
print("fzf vsplit underlay: ok")
