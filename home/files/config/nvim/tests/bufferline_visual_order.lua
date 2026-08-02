local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
package.path = vim.fs.joinpath(nvim_root, "lua/?.lua") .. ";" .. package.path

local first = vim.api.nvim_get_current_buf()
local second = vim.api.nvim_create_buf(true, false)
local third = vim.api.nvim_create_buf(true, false)
local group_marker = vim.api.nvim_create_buf(false, true)
local command_calls = 0
vim.api.nvim_create_user_command("BufferLineCycleNext", function()
	command_calls = command_calls + 1
	vim.api.nvim_win_set_buf(0, third)
end, {})

local function component(kind, id)
	return {
		type = kind,
		id = id,
		as_element = function(self)
			return { type = self.type, id = self.id }
		end,
	}
end

local state = {
	components = {
		component("buffer", first),
		component("buffer", third),
	},
	__components = {
		component("buffer", first),
		component("group", group_marker),
		component("buffer", second),
		component("buffer", third),
	},
}
package.loaded["bufferline.state"] = state
local cycle = require("config.bufferline").cycle

cycle("BufferLineCycleNext")
assert(command_calls == 1 and vim.api.nvim_get_current_buf() == third, "visible buffer must use BufferLine command")
vim.api.nvim_win_set_buf(0, second)
cycle("BufferLineCycleNext")
assert(vim.api.nvim_get_current_buf() == third, "hidden-group buffer must cycle in visual order")
state.__components = {
	component("buffer", first),
	component("group", group_marker),
	component("buffer", second),
}
vim.api.nvim_win_set_buf(0, second)
cycle("BufferLineCycleNext")
assert(vim.api.nvim_get_current_buf() == first, "hidden visual order must wrap")
state.__components = {
	component("buffer", first),
	component("group", group_marker),
	component("buffer", second),
	component("buffer", third),
}
vim.api.nvim_win_set_buf(0, second)
cycle("BufferLineCyclePrev")
assert(vim.api.nvim_get_current_buf() == first, "numeric group marker must not enter visual buffer order")
assert(command_calls == 1, "hidden buffer must not invoke BufferLine command")
print("bufferline visual order: ok")
