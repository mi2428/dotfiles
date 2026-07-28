local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
vim.opt.runtimepath:prepend(nvim_root)
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")

local specs = dofile(vim.fs.joinpath(nvim_root, "lua/plugins/ui.lua"))
local snacks
for _, spec in ipairs(specs) do
	if spec[1] == "folke/snacks.nvim" then
		snacks = spec
		break
	end
end
assert(snacks, "Snacks plugin spec was not found")

local popup_key
for _, key in ipairs(snacks.keys or {}) do
	if key[1] == "<C-S-Bslash>" then
		popup_key = key
		break
	end
end
assert(popup_key, "floating terminal key is missing")
assert(vim.deep_equal(popup_key.mode, { "n", "t" }), "floating terminal must toggle in normal and terminal modes")

local mapping_calls = 0
local original_popup_terminal = package.loaded["config.popup_terminal"]
package.loaded["config.popup_terminal"] = {
	toggle = function()
		mapping_calls = mapping_calls + 1
	end,
}
popup_key[2]()
package.loaded["config.popup_terminal"] = original_popup_terminal
assert(mapping_calls == 1, "floating terminal mapping did not call its dedicated toggle")

local toggle_call
local original_snacks = package.loaded.snacks
package.loaded.snacks = {
	terminal = {
		toggle = function(cmd, opts)
			toggle_call = { cmd = cmd, opts = opts }
			return "terminal"
		end,
	},
}
package.loaded["config.popup_terminal"] = nil
local result = require("config.popup_terminal").toggle()
package.loaded["config.popup_terminal"] = original_popup_terminal
package.loaded.snacks = original_snacks

assert(result == "terminal", "floating terminal must return the Snacks terminal instance")
assert(toggle_call.cmd == vim.o.shell, "floating terminal must use an explicit shell command")
assert(toggle_call.opts.count == 1, "floating terminal id must not depend on a mapping count")
assert(toggle_call.opts.win.position == "float", "floating terminal must use a popup window")
assert(toggle_call.opts.win.relative == "editor", "floating terminal must be centered relative to the editor")
assert(toggle_call.opts.win.width == 0.8, "floating terminal width must be 80%")
assert(toggle_call.opts.win.height == 0.8, "floating terminal height must be 80%")
assert(toggle_call.opts.win.wo.winbar == "", "floating terminal must not inherit the bottom terminal winbar")
assert(toggle_call.opts.win.wo.winfixheight == false, "floating terminal must not inherit split height locking")
assert(toggle_call.opts.win.wo.winfixwidth == false, "floating terminal must not lock its popup width")

print("floating terminal regression: ok")
