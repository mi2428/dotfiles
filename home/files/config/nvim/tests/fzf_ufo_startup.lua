local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
vim.opt.runtimepath:prepend(nvim_root)
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")

package.loaded["config.fzf"] = {
	ui_opts = function()
		return {}
	end,
	color_spec = function()
		return ""
	end,
}

local destination = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(destination, "fzf-ufo-startup.lua")
local opened
package.loaded["fzf-lua.actions"] = {
	file_edit_or_qf = function(selected, opts)
		opened = { selected = selected, opts = opts }
		vim.api.nvim_set_current_buf(destination)
	end,
}

local enabled_buf
package.loaded.ufo = {
	hasAttached = function(buf)
		return buf == destination
	end,
	enableFold = function(buf)
		enabled_buf = buf
	end,
}

local deferred = {}
vim.defer_fn = function(callback, delay)
	deferred[#deferred + 1] = { callback = callback, delay = delay }
end

local modes = { "t", "t", "n" }
local mode_index = 0
vim.api.nvim_get_mode = function()
	mode_index = mode_index + 1
	return { mode = modes[mode_index] or "n", blocking = false }
end

local specs = dofile(vim.fs.joinpath(nvim_root, "lua/plugins/core.lua"))
local fzf
for _, spec in ipairs(specs) do
	if spec[1] == "ibhagwan/fzf-lua" then
		fzf = spec
		break
	end
end
assert(fzf, "fzf-lua plugin spec was not found")

local selected = { "home/files/config/nvim/lua/plugins/ui.lua" }
local opts = { cwd = dotfiles_root }
fzf.opts.actions.files.enter(selected, opts)

assert(opened and opened.selected == selected and opened.opts == opts, "Enter must retain fzf-lua's file action")
assert(#deferred == 1 and deferred[1].delay == 50, "fold refresh must wait for fzf mode teardown")

for expected = 1, 3 do
	local item = table.remove(deferred, 1)
	assert(item, "fold refresh retry was not scheduled")
	item.callback()
	if expected < 3 then
		assert(enabled_buf == nil, "UFO must not apply folds while fzf remains in terminal mode")
		assert(#deferred == 1 and deferred[1].delay == 50, "terminal mode must schedule another fold retry")
	end
end

assert(enabled_buf == destination, "UFO must reapply folds to the selected file once normal mode is restored")

print("fzf UFO startup regression: ok")
